# jira.vim

jira.vim lets you browse, edit and create Jira issues with Vim.

## Configuration

Clone this repo into `~/.vim/bundle/jira.vim` and put these lines into your
`~/.config/nvim/init.vim`:

    Plugin 'L3viathan/jira.vim'

    let g:jira_user = 'your-jira-user'
    let g:jira_host = 'https://your.jira.instance.example'

You will be prompted for your Jira password upon your first usage of the plugin.
If this annoys you, you can set the environment variable `JIRAVIM_PASSWORD` to
your Jira password.

## Usage

### :JList
List non-closed issues assigned to me. In list mode, hit <cr> on an issue to open it.

### :JSearch
Search for issues using a JQL query.

### :JIssue
Open an existing issue. Requires an issue key like AUSU-1234. (Autocomplete for project, then for issue number.)
You can edit the follwing fields:

 * Summary
 * Assignee
 * Description

Add new comments at the end of the buffer.

*Limitations:* comments and workflow cannot be edited (yet).

### :JCreate
Create a new issue. Requires a project like AUSU, and an issue type like Story. (Autocomplete for project, then for issue type.)
