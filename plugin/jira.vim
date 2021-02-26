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

if !exists("g:jiravim_user") || !exists("g:jiravim_host")
    echom "jira.vim requires settings a user/host"
    finish
endif

py3 << ENDPYTHON
import os
import textwrap
import vim
try:
    import jira
except ImportError:
    import pip
    pip.main(["install", "jira"])

def input(message="input"):
    vim.command("call inputsave()")
    vim.command("let user_input = input('" + message + "')")
    vim.command("call inputrestore()")
    return vim.eval('user_input')

# only talk to JIRA server when we first execute a JIRA-related command
class DynamicJIRA:
    def __init__(self):
        self.jira = None
    def __getattr__(self, attr):
        if not self.jira:
            self.jira = jira.JIRA(
                vim.eval("g:jiravim_host").strip(),
                auth=(
                    vim.eval("g:jiravim_user").strip(),
                    os.environ.get("JIRAVIM_PASSWORD"),
                ),
            )
        return getattr(self.jira, attr)

j = DynamicJIRA()

def show_issue(issue_id):
    issue = j.issue(issue_id)
    fields = issue.fields()
    lines = [
        "{} - {}".format(issue_id, fields.summary),
        "Assignee: {}, Status: {}, Resolution: {}".format(
            fields.assignee.displayName,
            fields.status.name,
            getattr(fields.resolution, "name", "Unresolved"),
        ),
        "",
        "-"*60,
        "",
    ]
    lines.extend(textwrap.wrap(fields.description))
    lines.extend(["", "-"*60])
    for comment in fields.comment.comments:
        lines.append("")
        lines.extend(
            textwrap.wrap(
                "[{}] {}".format(
                    comment.author,
                    comment.body.replace("\r", ""),
                )
            )
        )
    new_buffer_with_lines(issue_id, lines)

def new_buffer_with_lines(filename, lines):
    vim.command("new")
    vim.current.buffer[:] = lines
    vim.command("setlocal buftype=nofile nomodifiable bufhidden=delete")
    vim.command("file {}".format(filename))
    vim.command("only")

def interactive_show_issue():
    issue_id = input("Enter issue ID: ")
    show_issue(issue_id)

def show_list(jql):
    lines = []
    for issue in j.search_issues(jql):
        lines.append("[{}] {}".format(issue.key, issue.fields.summary))
    new_buffer_with_lines("JIRA list", lines)
    vim.command("nnoremap <buffer> <cr> :py3 open_from_list()<cr>")

def open_from_list():
    bracketed_issue, _, _summary = vim.current.line.partition(" ")
    show_issue(bracketed_issue[1:-1])
ENDPYTHON

command! JShow :py3 interactive_show_issue()
command! JList :py3 show_list('assignee = ps AND status != closed')

" :new to create a buffer
" :setlocal buftype=nofile nomodifiable bufhidden=delete
" :file jira (sets the buffer name to "jira")
" :nnoremap <buffer> foo bar (maps foo to bar, BUT ONLY IN THIS BUFFER)
" Ideas for mappings: [r]eload, [c]omment, [a]ssign
" Ideas for commands: JCreate, JList, JSearch
" assignee = currentUser() AND status != closed
