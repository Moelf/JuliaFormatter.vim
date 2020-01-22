if get(g:, 'JuliaFormatter_loaded')
    finish
endif

function! s:PutLines(lines, lineStart)
    call append(a:lineStart - 1, a:lines)
endfunction

function! s:DeleteLines(lineFirst, lineLast)
    silent! exec a:lineFirst . "," . a:lineLast ."d _"
endfunction

function! s:AddPrefix(message) abort
    return '[JuliaFormatter] ' . a:message
endfunction

function! s:Echo(message) abort
    echomsg s:AddPrefix(a:message)
endfunction

function! s:Echoerr(message) abort
    echohl Error | echomsg s:AddPrefix(a:message) | echohl None
endfunction

" vim execute callback for every line.
function! s:HandleMessage(job, lines, event) abort
    if a:event ==# 'stdout'
        let l:message = json_decode(join(a:lines))
        if get(l:message, 'status') ==# 'success'
            let l:text = get(get(l:message, 'params'), 'text')
            call s:DeleteLines(g:line_start, g:line_end)
            call s:PutLines(split(l:text, '\n'), g:line_start)
        elseif get(l:message, 'status') ==# 'error'
            call s:Echoerr("ERROR: JuliaFormatter.jl could not parse text.")
        endif
    elseif a:event ==# 'stderr'
        " call s:Echo(join(a:lines))
    elseif a:event ==# 'exit'
        " call s:Echo('Done')
    endif
endfunction

function! s:HandleVim(job, data) abort
    return s:HandleMessage(a:job, [a:data], '')
endfunction

let s:root = expand('<sfile>:p:h:h')

function! JuliaFormatter#binaryPath() abort
    let l:filename = 'julia'
    if has('win32')
        let l:filename .= '.exe'
    endif
    return l:filename
endfunction

function! JuliaFormatter#Launch() abort

    call s:Echo("Launching stdio server")

    let l:binpath = JuliaFormatter#binaryPath()

    if executable(l:binpath) != 1
        call s:Echoerr('JuliaFormatter: binary (' . l:binpath . ') doesn''t exists! Please check installation guide.')
        return 0
    endif

    let l:cmd = join([l:binpath, '--startup-file=no', '--project=' . s:root, s:root . '/scripts/server.jl'])
    if has('nvim')
        let s:job = jobstart(l:cmd, {
                    \ 'on_stdout': function('s:HandleMessage'),
                    \ 'on_stderr': function('s:HandleMessage'),
                    \ 'on_exit': function('s:HandleMessage'),
                    \ })
        if s:job == 0
            call s:Echoerr('JuliaFormatter: Invalid arguments!')
            return 0
        elseif s:job == -1
            call s:Echoerr('JuliaFormatter: ' . l:binpath .' not executable!')
            return 0
        else
            let g:JuliaFormatter_loaded = 1
            return 1
        endif
    elseif has('job')
        " FIXME: stdout callback should fire after job finishes
        let s:job = job_start(l:cmd, {
                    \ 'out_cb': function('s:HandleVim'),
                    \ 'err_cb': function('s:HandleVim'),
                    \ 'exit_cb': function('s:HandleVim'),
                    \ })
        if job_status(s:job) !=# 'run'
            call s:Echoerr('JuliaFormatter: job failed to start or died!')
            return 0
        else
            let g:JuliaFormatter_loaded = 1
            return 1
        endif
    else
        echoerr 'Not supported: not nvim nor vim with +job.'
        return 0
    endif
endfunction

function! JuliaFormatter#Write(message) abort
    let l:message = a:message . "\n"
    if has('nvim')
        " jobsend respond 1 for success.
        return !jobsend(s:job, l:message)
    elseif has('channel')
        return ch_sendraw(s:job, l:message)
    else
        echoerr 'Not supported: not nvim nor vim with +channel.'
    endif
endfunction

function! JuliaFormatter#Send(method, params) abort
    let l:params = a:params
    return JuliaFormatter#Write(json_encode({
                \ 'method': a:method,
                \ 'params': l:params,
                \ }))
endfunction

function! JuliaFormatter#handleVimLeavePre() abort
    try
        return JuliaFormatter#Send('quit', {})
    catch
    endtry
endfunction

" JuliaFormatter#Format
function! JuliaFormatter#Format(m) abort
    if !get(g:, 'JuliaFormatter_loaded')
        call JuliaFormatter#Launch()
    end
    " visual mode == 1
    if a:m == 1
        let g:line_start = getpos("'<")[1]
        let g:line_end = getpos("'>")[1]
    else
        " Get all lines in the file
        let g:line_start =  1
        let g:line_end = line('$')
    endif
    let l:content = getline(g:line_start, g:line_end)
    let l:content = join(l:content, '\n')
    return JuliaFormatter#Send('format', {'text': l:content})
endfunction