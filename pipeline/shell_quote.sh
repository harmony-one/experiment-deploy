shell_quote() {
	local r sep
	sep=""
	for r
	do
		echo -n "${sep}'"
		sep=" "
		while :
		do
			# avoid ${r} from being interpreted as echo option
			case "${r}" in
			*"'"*)
				echo -n "X${r%%"'"*}'\\''" | sed 's/^X//'
				r="${r#*"'"}"
				;;
			*)
				echo -n "X${r}" | sed 's/^X//'
				break
				;;
			esac
		done
		echo -n "'"
	done
}
