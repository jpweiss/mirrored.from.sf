setxkbmap -option
setxkbmap -rules xorg -model generic
setxkbmap -layout us \
    -rules xorg \
    -symbols 'pc(pc105)' \
    -geometry 'pc(pc105)' \
    -types 'complete' \
    -compat 'complete'\
    -option 'altwin:menu+altwin:meta_alt+altwin:super_win'
setxkbmap

