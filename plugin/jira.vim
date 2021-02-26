" jira.vim
" Author: Jonathan Oberländer
" Created: Wed Feb 17 10:28:59 2021 +0100
" Requires: Vim Ver8.0+
" Version 0.1
"
" Documentation:
"   This plugin interfaces with JIRA

if v:version < 800 || !has('python3')
    echom "jira.vim requires vim8.0+ with Python 3."
    finish
endif

if exists("g:load_jiravim")
    finish
endif
let g:load_jiravim = "1"

if !exists("g:jira_user") || !exists("g:jira_host")
    echom "jira.vim requires settings a user/host"
    finish
endif

py3 << ENDPYTHON
import os
import re
import textwrap
import vim
try:
    import jira
except ImportError:
    import pip
    pip.main(["install", "jira"])
    import jira

def input(message="input"):
    vim.command("call inputsave()")
    vim.command("let user_input = input('" + message + "')")
    vim.command("call inputrestore()")
    return vim.eval('user_input')

def inputsecret(message="input"):
    vim.command("call inputsave()")
    vim.command("let user_input = inputsecret('" + message + "')")
    vim.command("call inputrestore()")
    return vim.eval('user_input')

# only talk to JIRA server when we first execute a JIRA-related command
class DynamicJIRA:
    def __init__(self):
        self.jira = None
    def __getattr__(self, attr):
        if not self.jira:
            user = vim.eval("g:jira_user").strip()
            password = os.environ.get("JIRAVIM_PASSWORD") or inputsecret("Jira password for {}: ".format(user))
            self.jira = jira.JIRA(
                vim.eval("g:jira_host").strip(),
                auth=(user, password),
            )
        return getattr(self.jira, attr)

j = DynamicJIRA()
issue_cache = {}

def show_issue(issue_key, reuse_buffer=False):
    issue = j.issue(issue_key)
    fields = issue.fields()
    issue_cache[issue_key] = (issue, fields)
    lines = [
        "{} - {}".format(issue_key, fields.summary),
        "Assignee: {}, Status: {}, Resolution: {}".format(
            getattr(fields.assignee, "name", "Unassigned"),
            fields.status.name,
            getattr(fields.resolution, "name", "Unresolved"),
        ),
        "",
        "-"*60,
        "",
    ]
    # lines.extend(fields.description.replace("\r", "").split("\n"))
    lines.extend(fields.description.split("\n"))
    lines.extend(["", "-"*60])
    for comment in fields.comment.comments:
        lines.append("")
        lines.extend(
            "[{}] {}".format(
                comment.author,
                # comment.body.replace("\r", ""),
                comment.body,
            ).split("\n")
        )
    new_buffer_with_lines(issue_key, lines, reuse_buffer=reuse_buffer)

def new_buffer_with_lines(filename, lines, reuse_buffer=False):
    if not reuse_buffer:
        vim.command("new")
    vim.current.buffer[:] = lines
    vim.command("setlocal buftype=acwrite modifiable bufhidden=hide nomodified")
    vim.command("file {}".format(filename))
    vim.command("only")
    vim.command("nnoremap <buffer> <cr> :py3 open_issue_under_cursor()<cr>")
    vim.command("nnoremap <buffer> <bs> :bprev<cr>")
    vim.command("augroup jira")
    vim.command("au! * <buffer>")
    vim.command("au BufWriteCmd <buffer> py3 update_issue_from_buffer()")
    vim.command("augroup END")

def interactive_show_issue():
    issue_key = input("Enter issue ID: ")
    show_issue(issue_key)

def show_list(jql):
    lines = []
    for issue in j.search_issues(jql):
        lines.append("[{}] {}".format(issue.key, issue.fields.summary))
    new_buffer_with_lines("JIRA issues", lines)

def add_comment(issue_key, comment):
    ...
    j.add_comment(issue_key, comment)

def open_issue_under_cursor():
    cword = vim.eval('expand("<cWORD>")')
    issue_key = re.search(r'[A-Z]+-\d+', cword).group()
    show_issue(issue_key)

def update_issue_from_buffer():
    _path, filename = os.path.split(vim.current.buffer.name)
    if re.search(r'[A-Z]+-\d+', filename).group():
        issue_key = filename
        something_changed = False
        # it is an issue key
        # TODO: get all (editable) fields from buffer
        # - Title: done
        # - Assignee: done
        # - Description
        _, __, summary = vim.current.buffer[0].partition(" - ")

        issue, fields = issue_cache[issue_key]
        temp, _, __ = vim.current.buffer[1].partition(",")
        _, __, assignee = temp.partition(": ")
        assignee = assignee.strip()

        description = []
        for line in vim.current.buffer[5:]:
            if line == "-"*60:
                description.pop()
                break
            description.append(line)
        description = "\r\n".join(description)

        if assignee != getattr(fields.assignee, "name", ""):
            j.assign_issue(issue, assignee or None)
            something_changed = True

        if summary != fields.summary:
            issue.update(fields={"summary": summary})
            something_changed = True

        if something_changed:
            show_issue(issue_key, reuse_buffer=True)

ENDPYTHON

command! JShow :py3 interactive_show_issue()
command! JList :py3 show_list('assignee = currentUser() AND status != closed')

" Ideas for mappings: [r]eload, [c]omment, [a]ssign
" Ideas for commands: JCreate, JSearch
" Todo: Update after editing buffer
