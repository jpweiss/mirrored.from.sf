setxkbmap -v -option
setxkbmap -v -rules evdev -model generic
setxkbmap -v -layout us \
    -rules evdev \
    -symbols 'pc(pc105)' \
    -geometry 'pc(pc105)' \
    -types 'complete' \
    -compat 'complete'\
    -option 'altwin:menu+altwin:meta_alt+altwin:super_win'
setxkbmap -v

