#!/bin/bash


# The default test options.
for opt in numlk:{invert,un_ctrl} mousekeys:alt altwin:fn_super; do
    DEFLT_TEST_OPTS="$DEFLT_TEST_OPTS -option $opt"
done


usage() {
    echo "usage: $0 [-default|-o|-option|-opts] [<outputNameBase>]"
    echo "<outputNameBase> will have extentions added."
    echo ""

    defoptMesg=`echo -e "${DEFLT_TEST_OPTS//-o/\n\t-o}"`

    cat <<-EOF
	Options:
	
	-defl
	-default
	    Output and compile the default ThinkPad X40 map.  I.e., run
        'setxkbmap' with no '-option' args.
	    All other options passed to $0 are ignored.

	-o <xkbmapOption>
	-option <xkbmapOption>
	    Include the specified option on the commandline to the 'setxkbmap'
	    call.
	    Options that are present by default are:  $defoptMesg

	-opts <xtra-setxkbmap-options>
	    Add the string "<xtra-setxkbmap-options>" to the 'setxkbmap' call, as
	    listed.

	Any non-option parameter is used as the base of the output filename.  (If
	you specify more than one, only the last one is used.)  Appropriate
	extensions are appended (so don't include any).

	Example:

	    $0 -option wheelButtons_norep verify-latest

EOF

    exit 0
}


testOptions="$DEFLT_TEST_OPTS"
nameBase=xkb-verify
while [ -n "$1" ]; do
    case "$1" in
        -o|-option)
            shift
            testOptions="$testOptions -option $1"
            ;;
        -opts)
            shift
            testOptions="$testOptions $1"
            ;;
        -def*)
            testOptions=""
            nameBase=tpX40-deflt
            set --
            ;;
        -h|--help)
            usage
            ;;
        *)
            nameBase="$1"
            ;;
    esac
    shift
done

echo "Creating '${nameBase}.map'"
if [ -n "$testOptions" ]; then
    echo -e "    Using options:${testOptions//-o/\n\t-o}"
fi
setxkbmap -option -rules thinkpadx40 -model thinkpadx40 $testOptions \
     -print > ${nameBase}.map

echo "Creating '${nameBase}.xkb'"
xkbcomp -a -w 1 -xkb -dflts -o ${nameBase}.xkb ${nameBase}.map

