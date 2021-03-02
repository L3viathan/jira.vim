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

SEPARATOR = "-" * 60
ADD_COMMENT_TEXT = "To add a comment, write below this line and save:"

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
            if line == SEPARATOR:
                description.pop()
                break
            description.append(line)
        description = "\r\n".join(description)

        new_comment = []
        for line in reversed(vim.current.buffer):
            if line == ADD_COMMENT_TEXT and new_comment[0] == SEPARATOR:
                if len(new_comment) > 1:
                    j.add_comment(issue_key, "\r\n".join(new_comment[1:]))
                    something_changed = True
                break
            new_comment.insert(0, line)

        if assignee != getattr(fields.assignee, "name", ""):
            j.assign_issue(issue, assignee or None)
            something_changed = True

        if summary != fields.summary:
            issue.update(fields={"summary": summary})
            something_changed = True

        if description != fields.description:
            issue.update(fields={"description": description})
            something_changed = True

        if something_changed:
            show_issue(issue_key, reuse_buffer=True)

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
        SEPARATOR,
        "",
    ]
    lines.extend(fields.description.replace("\r", "").split("\n"))
    lines.extend(["", SEPARATOR])
    for comment in fields.comment.comments:
        lines.append("")
        lines.extend(
            "[{}] {}".format(
                comment.author,
                comment.body.replace("\r", ""),
            ).split("\n")
        )
    lines.extend(["", SEPARATOR, ADD_COMMENT_TEXT, SEPARATOR])
    new_buffer_with_lines(issue_key, lines, reuse_buffer=reuse_buffer)

def show_issues(jql):
    lines = [
        "[{}] {}".format(issue.key, issue.fields.summary)
        for issue in j.search_issues(jql)
    ]
    new_buffer_with_lines("JIRA issues", lines)

def create_issue(project, issuetype):
    summary = input("{} issue summary: ".format(project))
    issue = j.create_issue(
        project=project,
        summary=summary,
        description="(placeholder)",
        issuetype={"name": issuetype},
    )
    show_issue(issue.key)

def reload_issue():
    _path, filename = os.path.split(vim.current.buffer.name)
    if re.search(r'[A-Z]+-\d+', filename).group():
        issue_key = filename
        show_issue(issue_key, reuse_buffer=True)


def complete_jira(prefix, cmdline):
    if cmdline.count(" ") == 2:
        # suggest issuetypes
        project = cmdline.split()[1]
        meta = [
            p
            for p in j.createmeta(projectKeys=project)["projects"]
            if p["key"] == project
        ][0]
        return [
            issuetype["name"]
            for issuetype in meta["issuetypes"]
            if issuetype["name"].startswith(prefix)
        ]
    # if no dash in prefix: suggest all projects
    if "-" not in prefix or cmdline.startswith("JCreate"):
        # auto-complete project only
        to_dash_or_not_to_dash = "" if cmdline.startswith("JCreate") else "-"
        return [
            "{}{}".format(project.key, to_dash_or_not_to_dash)
            for project in j.projects() if project.key.startswith(prefix)
        ]
    else:
        # auto-complete entire issue (i.e. project and number)
        project = prefix.split("-")[0]
        jql = "project = '{}' ORDER BY key DESC".format(project)
        return [
            issue.key
            for issue in j.search_issues(jql)
            if issue.key.startswith(prefix)
        ]

ENDPYTHON

function! CompleteJira(arglead, cmdline, cursorpos)
    return py3eval('complete_jira("' . a:arglead . '", "' . a:cmdline . '")')
endfunction

command! -complete=customlist,CompleteJira -nargs=1 JIssue :py3 show_issue(<f-args>)
command! JList :py3 show_issues('assignee = currentUser() AND status != closed')
command! -nargs=+ JSearch :py3 show_issues(<q-args>)
command! JReload :py3 reload_issue()
command! -complete=customlist,CompleteJira -nargs=+ JCreate :py3 create_issue(<f-args>)

" Ideas for commands: JCreate
" Todo: Update after editing buffer
