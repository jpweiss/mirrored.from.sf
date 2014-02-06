sudo rm /var/lib/xkb/server-*.xkm
setxkbmap -v -option
setxkbmap -v -rules thinkpadx40 -model thinkpadx40 \
    -option fn:fn_super_win \
    -option numlk:invert \
    -option numlk:un_ctrl \
    -option mousekeys:alt
setxkbmap -v
