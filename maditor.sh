#!/bin/sh

PARSED_STRING=""
FILE_CONTENTS=""
CURR_FILE=""
UNDO_KEEP=""
REDO_KEEP=""

READER="cat"
EDITOR="vi"

check_file() {

	if ! [ -f "$CURR_FILE" ]; then
		echo "(!) File $CURR_FILE not found."
		return 1
	fi

	if [ -z "$FILE_CONTENTS" ]; then
		echo "(!) Empty file."
		return 2
	fi

	return 0
}

pre_parse() {

	printf '%s\n' "$FILE_CONTENTS" \
	| grep -n '^#' \
	| sed -n 's/^\([0-9]\+\):\(#\+\)\s\(.*\)$/\1\t\2\t\3/p' \
	| awk -F'\t' -v wcount=`printf '%s\n' "$FILE_CONTENTS" | wc -l` '
	{
		if (NR == 1) {
			first_sect = $2
		}
		print $0
	}

	END {
		print wcount + 1 "\t" first_sect "\tEOF"
	}' \
	| awk -F'\t' '

	function set_prev() {

		prevl = $1
		prevs = $2
		prevn = $3
	}

	function arr_to_str(arr, len, sep) {

		arr_string = ""

		for (i = 0; i < len; i++) {
			if (i < len - 1)
				arr_string = arr_string arr[i] sep
			else
				arr_string = arr_string arr[i]
		}

		return arr_string
	}

	function reset_after(arr, len, pos, repl) {

		if (pos >= len) {
			return
		}

		for (i = pos; i < len; i++) {
			arr[i] = repl
		}
	}

	{
		if (NR == 1) {
			set_prev()
			first_sect = $2
			section_length = length($2)
			section[section_length - 1] = 1
		}
		else {
			section[length($2) - 1] += 1

			if (length($2) < length(prevs)) {
				reset_after(section, section_length, \
					    length($2), 0)
			}

			section_length = length($2)

			set_prev()
		}

		print $1 "\t" $2 "\t" \
		      arr_to_str(section, section_length, ".") "\t" $3
	}'
}

human_readable() {

	printf '%s\n' "$1" \
	| awk -F'\t' -v wcount=`echo "$1" | wc -l` '

	{
		if (wcount == NR) {
			exit 0
		}

		tab_string = ""
		for (i = 0; i < length($2) - 1; i++) {
			tab_string = tab_string "\t"
		}
		print tab_string $3 ". " $4
	}'
}

sect_range() {

	SECTION=`echo $2 | sed 's/^\(.*\)\.$/\1/g'`

	printf '%s\n' "$1" \
	| awk -F'\t' -v sect="$SECTION" '

	{
		if (!sect_found) {
			if ($3 == sect) {
				sect_found = 1
				lstart = $1
				sect_md = $2
			}
		}
		else if (length(sect_md) >= length($2)) {
			exit 0
		}
	}

	END {
		if (!sect_found) {
			exit 1
		}
		else {
			print "start:" lstart \
			     ":lines:" $1 - lstart \
			     ":end:" $1 - 1
		}
	}'
}

md_files_check() {

	if [ -z "$MD_FILES" ]; then
		echo "(!) No md files found or" \
		     "not loaded (use: getmds)"
		return 1
	fi

	return 0
}

read_range() {

	NUM_LINES="`echo "$2-$1" | awk -F'-' '{ print $1 - $2 }'`"
	output "`printf '%s' "$FILE_CONTENTS" | sed -n "$1,$2p"`" "$NUM_LINES"
}

edit_range() {

	TEMP_FILE=""
	TEMP_FILE_MD5=""

	if [ -z "$3" ]; then
		TEMP_FILE="`mktemp`"
		read_range $1 $2 > "$TEMP_FILE"

		TEMP_FILE_MD5="`md5sum "$TEMP_FILE" | awk '{ print $1 }'`"

		$EDITOR "$TEMP_FILE"

		NEW_MD5="`md5sum "$TEMP_FILE" | awk '{ print $1 }'`"

		if [ "$NEW_MD5" = "$TEMP_FILE_MD5" ]; then
			rm "$TEMP_FILE"
			return 0
		fi
	elif [ "$3" != "delete" ]; then
		echo "(!) Internal bug!"
		exit -1
	fi

	KEEP_UNTIL="`printf '%s\n' "$1" | awk '{ print $1 - 1 }'`"
	KEEP_AFTER="`printf '%s\n' "$2" | awk '{ print $1 + 1 }'`"

	FIRST_PART="`printf '%s\n' "$FILE_CONTENTS" \
		    | sed -n "1,${KEEP_UNTIL}p"`"
	SECOND_PART="`printf '%s\n' "$FILE_CONTENTS" \
		    | sed -n "${KEEP_AFTER},\\$p"`"

	UNDO_KEEP="$FILE_CONTENTS"

	if [ "$3" != "delete" ]; then
		CHANGES="`cat "$TEMP_FILE"`"
		CHANGES_NUML=`echo "$CHANGES" | wc -l`
		TEMP_FILE_NUML=`cat "$TEMP_FILE" | wc -l`
		if [ "$TEMP_FILE_NUML" -ge $CHANGES_NUML ]; then
			FILE_CONTENTS=\
"${FIRST_PART}

${CHANGES}

${SECOND_PART}"
		else
			FILE_CONTENTS=\
"${FIRST_PART}

${CHANGES}
${SECOND_PART}"
		fi
		rm "$TEMP_FILE"
	else
		FILE_CONTENTS="${FIRST_PART}${SECOND_PART}"
	fi
}

output() {
	if [ "$2" = "FORCE_ECHO" ]; then
		echo "$1" | "$READER"
	else
		NUM_LINES=`echo "$1" | wc -l`
		if [ "$2" -ge $NUM_LINES ]; then
			printf '%s\n\n' "$1" | "$READER"
		else
			printf '%s\n' "$1" | "$READER"
		fi
	fi
}

print_help() {

	HELP_STRING=\
"\tloadfn <fname>\t\tload file\n\
\tgetmds\t\t\tfind md files in subfolders\n\
\tshowmds\t\t\tshow found md files\n\
\tload f<num>\t\tload file from getmds table\n\
\n\
\treparse\t\t\treparse file\n\
\toutput\t\t\tprint parsed output\n\
\tpretty\t\t\tpretty print parsed output\n\
\n\
\trange <sect>\t\tshow section range\n\
\tread <sect>\t\tshow section contents\n\
\tedit <sect>\t\tedit section\n\
\tmove <src> <dest>\tmove section\n\
\tdelete <sect>\t\tdelete section\n\
\n\
\tshowread\t\tshow current reader\n\
\tsetread <comm>\t\tset text reader\n\
\tshowedit\t\tshow current text editor\n\
\tsetedit <comm>\t\tset text editor\n\
\n\
\tundo\t\t\tundo\n\
\tredo\t\t\tredo\n\
\n\
\thelp\t\t\tshow this\n\
\tquit\t\t\tquit"

	output "$HELP_STRING" FORCE_ECHO
}

while [ 1 ]; do

	echo -n "> "
	read INPUT

	case $INPUT in
		help)
			print_help
			;;

		getmds)
			MD_FILES="`find -name '*.md' \
				  | awk '{ print "f" NR "\t" $0 }'`"

			md_files_check
			if [ "$?" -ne 0 ]; then
				echo "(!) No md files found"
				continue
			fi

			printf '%s\n' "$MD_FILES"
			;;

		showmds)
			md_files_check

			if [ "$?" -ne 0 ]; then
				continue
			fi

			printf '%s\n' "$MD_FILES"
			;;

		loadfn\ *|load\ *)
			printf '%s\n' "$INPUT" | grep 'loadfn' > /dev/null

			if [ "$?" -ne 0 ]; then

				md_files_check

				if [ "$?" -ne 0 ]; then
					continue
				fi

				FPT="`printf '%s\n' "$INPUT" \
				     | awk '{ print $2 }'`"

				CURR_FILE="`printf '%s\n' "$MD_FILES" \
					   | grep "$FPT" \
					   | awk -F'\t' '{ print $2 }'`"

				if [ -z "$CURR_FILE" ]; then
					echo "(!) Invalid file pointer." \
					     "See: showmds"
					continue
				fi

			else
				CURR_FILE="`printf '%s\n' "$INPUT" \
					   | awk '{ print $2 }'`"

				if [ -z "$CURR_FILE" ]; then
					echo "(!) No file name given."
					continue
				fi
			fi

			if ! [ -f "$CURR_FILE" ]; then
				echo "(!) File $CURR_FILE not found."
				continue
			fi

			FILE_CONTENTS="`cat "$CURR_FILE"`"

			check_file
			if [ "$?" -ne 0 ]; then
				continue
			fi

			PARSED_STRING="`pre_parse`"

			if [ -z "$PARSED_STRING" ]; then
				echo "(!) String not parsed or wrong format."
				CURR_FILE=""
				FILE_CONTENTS=""
				continue
			fi

			output "`human_readable "$PARSED_STRING"`"
			;;

		pretty)
			check_file
			if [ "$?" -ne 0 ]; then
				continue
			fi

			output "`human_readable "$PARSED_STRING"`"
			;;
		output)
			check_file
			if [ "$?" -ne 0 ]; then
				continue
			fi

			output "$PARSED_STRING"
			;;

		range\ *|read\ *|edit\ *|delete\ *)
			check_file
			if [ "$?" -ne 0 ]; then
				continue
			fi

			SECT=`printf '%s\n' "$INPUT" | awk '{ print $2 }'`

			if [ -z "$SECT" ]; then
				echo "(!) Please input section."
				continue
			fi

			RANGE=`sect_range "$PARSED_STRING" "$SECT"`

			if [ "$?" -ne 0 ]; then
				echo "(!) Could not find section: $SECT"
				continue
			fi

			printf '%s\n' "$INPUT" | grep '^range ' > /dev/null

			if [ "$?" -eq 0 ]; then
				echo "$RANGE" \
				| awk -F':' '
				{
					print $1 ": " $2
					print $3 ": " $4
					print $5 ": " $6
				}'
				continue
			fi

			RANGE_ARGS="`printf '%s\n' "$RANGE" \
				    | awk -F':' ' { print $2 OFS $6 }'`"

			printf '%s\n' "$INPUT" | grep '^read ' > /dev/null

			if [ "$?" -eq 0 ]; then
				read_range $RANGE_ARGS
			fi

			printf '%s\n' "$INPUT" | grep '^edit ' > /dev/null

			if [ "$?" -eq 0 ]; then
				edit_range $RANGE_ARGS
			fi

			printf '%s\n' "$INPUT" | grep '^delete ' > /dev/null

			if [ "$?" -eq 0 ]; then
				edit_range $RANGE_ARGS delete
			fi

			printf '%s\n' "$INPUT" \
			| grep '^delete \|^edit ' > /dev/null

			if [ "$?" -eq 0 ]; then
				PARSED_STRING=`pre_parse`

				if [ -z "$PARSED_STRING" ]; then
					echo "(!) String not parsed or wrong format."
					CURR_FILE=""
					FILE_CONTENTS=""
					continue
				fi
			fi
			;;
		showread)
			echo "\"$READER\""
			;;
		setread\ *)
			PARAM="`echo "$INPUT" \
			       | sed -n 's/^setread \(.*\)$/\1/p'`"

			if [ -z "$PARAM" ]; then
				echo "(!) Please set command as argument."
			fi

			READER="$PARAM"
			;;

		showedit)
			echo "\"$EDITOR\""
			;;
		setedit\ *)
			PARAM="`echo "$INPUT" \
			       | sed -n 's/^setedit \(.*\)$/\1/p'`"

			if [ -z "$PARAM" ]; then
				echo "(!) Please set command as argument."
			fi

			EDITOR="$PARAM"
			;;
		undo)
			if ! [ -z "$UNDO_KEEP" ]; then
				REDO_KEEP="$FILE_CONTENTS"
				FILE_CONTENTS="$UNDO_KEEP"
				UNDO_KEEP=""
			else
				echo "(*) Nothing to undo."
			fi
			;;
		redo)
			if ! [ -z "$REDO_KEEP" ]; then
				UNDO_KEEP="$FILE_CONTENTS"
				FILE_CONTENTS="$REDO_KEEP"
				REDO_KEEP=""
			else
				echo "(*) Nothing to redo."
			fi
			;;
		quit|exit)
			break
			;;
		*)
			echo "(!) Unknown command: $INPUT. Try help."
			;;
	esac

done
