. "${progdir}/msg.sh"

unset -v tac

for tac in $(which -a tac) 'tail -r'
do
	case $(
		(echo omg; echo wtf; echo bbq) |
			${tac} 2> /dev/null |
			tr -d '\n'
	) in
	bbqwtfomg)
		msg "found working tac: ${tac}"
		break
		;;
	esac
	tac=
done

case "${tac}" in
"") err 69 "cannot find working tac";;
esac
