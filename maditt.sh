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

	printf '%s' "$FILE_CONTENTS" \
	| awk '
	BEGIN {
		parsing = 1
	}
	{
		if ($0 ~ /^```.*$/) {
			if (parsing == 1) {
				parsing = 0
			}
			else {
				parsing = 1
			}
			print QUOTE
		}
		else {
			if (parsing == 1) {
				print $0
			}
			else {
				print QUOTE
			}
		}
	}' \
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

load_file() {

	COMM="$1"

	printf '%s' "$COMM" | grep 'loadfn ' > /dev/null

	if [ "$?" -ne 0 ]; then

		md_files_check

		if [ "$?" -ne 0 ]; then
			return 1
		fi

		FPT="`printf '%s' "$COMM" \
		    | awk '{ print $2 }'`"

		CURR_FILE="`printf '%s' "$MD_FILES" \
			  | grep "$FPT" \
			  | awk -F'\t' '{ print $2 }'`"

		if [ -z "$CURR_FILE" ]; then
			echo "(!) Invalid file pointer." \
			     "See: showmds"
			return 2
		fi

	else
		CURR_FILE="`printf '%s' "$COMM" \
			  | sed -n 's/^loadfn \(.*\)$/\1/p'`"

		if [ -z "$CURR_FILE" ]; then
			echo "(!) No file name given."
			return 3
		fi
	fi

	if ! [ -f "$CURR_FILE" ]; then
		echo "(!) File $CURR_FILE not found."
		return 4
	fi

	FILE_CONTENTS="`cat "$CURR_FILE"; echo .`"
	FILE_CONTENTS="${FILE_CONTENTS%.}"

	check_file
	if [ "$?" -ne 0 ]; then
		return 5
	fi

	PARSED_STRING="`pre_parse`"

	if [ -z "$PARSED_STRING" ]; then
		echo "(!) String not parsed or wrong format."
		CURR_FILE=""
		FILE_CONTENTS=""
		return 6
	fi

	output "(!) Successfully loaded file: $1" NL

	return 0
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

	SECTION=`echo "$2" | sed 's/^\(.*\)\.$/\1/g'`

	printf '%s\n' "$1" \
	| awk -F'\t' -v sect="$SECTION" '

	{
		if (!sect_found) {
			if ($3 "" == sect "") {
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
			if (lstart < $1) {
				print "start:" lstart \
				     ":lines:" $1 - lstart \
				     ":end:" $1 - 1
				exit 0
			}

			exit 2
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

	TO_OUTPUT="`printf '%s' "$FILE_CONTENTS" | sed -n "$1,$2p"; echo .`"
	output "${TO_OUTPUT%.}"
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
	fi

	KEEP_UNTIL="`printf '%s\n' "$1" | awk '{ print $1 - 1 }'`"
	KEEP_AFTER="`printf '%s\n' "$2" | awk '{ print $1 + 1 }'`"

	if [ "$1" -eq 1 ]; then
		FIRST_PART=""
	else
		FIRST_PART="`printf '%s\n' "$FILE_CONTENTS" \
			    | sed -n "1,${KEEP_UNTIL}p"; echo .`"
		FIRST_PART="${FIRST_PART%.}"
	fi

	SECOND_PART="`printf '%s\n' "$FILE_CONTENTS" \
		    | sed -n "${KEEP_AFTER},\\$p"; echo .`"
	SECOND_PART="${SECOND_PART%.}"

	UNDO_KEEP="$FILE_CONTENTS"

	if [ -z "$3" ]; then
		CHANGES="`cat "$TEMP_FILE"; echo .`"
		CHANGES="${CHANGES%.}"
		FILE_CONTENTS="${FIRST_PART}${CHANGES}${SECOND_PART}"
		rm "$TEMP_FILE"
	else
		case $3 in
			delete)
				FILE_CONTENTS="${FIRST_PART}${SECOND_PART}"
				;;
			flatten)
				CHANGES="`read_range $1 $2 \
					 | sed '2,$s/^#\(#.*\)$/\1/g'; echo .`"
				FILE_CONTENTS="${FIRST_PART}${CHANGES%.}${SECOND_PART}"
				;;
		esac
	fi
}

range_ops() {

	COMM="$1"

	check_file
	if [ "$?" -ne 0 ]; then
		return 1
	fi

	SECT=`printf '%s' "$COMM" | awk '{ print $2 }'`

	if [ -z "$SECT" ]; then
		echo "(!) Please input section."
		return 2
	fi

	RANGE=`sect_range "$PARSED_STRING" "$SECT"`

	if [ "$?" -ne 0 ]; then
		echo "(!) Could not find section: $SECT"
		return 3
	fi

	printf '%s' "$COMM" | grep '^range ' > /dev/null

	if [ "$?" -eq 0 ]; then
		echo "$RANGE" \
		| awk -F':' '
		{
			print $1 ": " $2
			print $3 ": " $4
			print $5 ": " $6
		}'
		return 0
	fi

	RANGE_ARGS="`printf '%s' "$RANGE" \
		    | awk -F':' '{ print $2 OFS $6 }'`"

	case $COMM in
		read\ *)
			read_range $RANGE_ARGS
			;;
		edit\ *)
			edit_range $RANGE_ARGS
			;;
		delete\ *)
			edit_range $RANGE_ARGS delete
			;;
		flatten\ *)
			edit_range $RANGE_ARGS flatten
			;;
		*)
			return 4
			;;
	esac

	case $COMM in
		delete\ *|edit\ *|flatten\ *)
			refresh
		;;
	esac

	return 0
}

refresh() {
	PARSED_STRING=`pre_parse`

	if [ -z "$PARSED_STRING" ]; then
		echo "(!) String not parsed or wrong format."
		CURR_FILE=""
		FILE_CONTENTS=""
		return 4
	fi
}

save_changes() {
	cp "$CURR_FILE" "$CURR_FILE.backup"

	output "$FILE_CONTENTS" > "$CURR_FILE"
}

output() {
	if [ "$2" = "FORCE_ECHO" ]; then
		echo "$1" | "$READER"
	elif [ "$2" = "NL" ]; then
		printf '%s\n' "$1" | "$READER"
	else
		printf '%s' "$1" | "$READER"
	fi
}

try_quit() {

	if [ -z "$CURR_FILE" ]; then
		return 0
	fi

	ORIGINAL_CONTENTS="`cat "$CURR_FILE"; echo .`"
	ORIGINAL_CONTENTS="${ORIGINAL_CONTENTS%.}"

	SAVE_INPUT=""

	if ! [ "$ORIGINAL_CONTENTS" = "$FILE_CONTENTS" ]; then
		while [ 1 ]; do

			echo -n "(*) Save changes? (yes/no/cancel) "
			read SAVE_INPUT

			case $SAVE_INPUT in
				yes)
					save_changes
					echo "(i) Changes saved!"
					return 0
					;;
				no)
					echo "(i) Exiting..."
					return 0
					;;
				cancel)
					return 1
					;;
				*)
					continue
					;;
			esac
		done
	else
		return 0
	fi

	return 2 # bug
}

trap_sigint() {
	try_quit && exit 0
	return 0
}

print_help() {

	HELP_STRING=\
"loadfn <fname>;load file\n\
getmds;find md files in subfolders\n\
showmds;show found md files\n\
load f<num>;load file from getmds table\n\
save;save changes\n\
\n\
output;print parsed output (debug)\n\
pretty;pretty print parsed output\n\
\n\
range <sect>;show section range\n\
read <sect>;show section contents\n\
edit <sect>;edit section\n\
\n\
move <src> <dest>;move section\n\
delete <sect>;delete section\n\
flatten <sect>;flatten section\n\
\n\
showread;show current reader\n\
setread <comm>;set text reader\n\
showedit;show current text editor\n\
setedit <comm>;set text editor\n\
\n\
undo;undo\n\
redo;redo\n\
\n\
help;show this\n\
quit;quit"

	output "$HELP_STRING" FORCE_ECHO | column -t -e -s';'
}

print_header() {
	HEADER_STRING=\
"\nMaDiTT: A powerful MarkDown ediTTor.\n\n\
\tAuthor: Stjepan Poljak\n\
\tE-Mail: stjepan.poljak@protonmail.com\n\
\tYear: 2020\n\n\
\tType 'help' to get started.\n"

	output "$HEADER_STRING" FORCE_ECHO
}

trap trap_sigint INT

print_header

if ! [ -z "$1" ]; then
	load_file "loadfn $1"
fi

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
			load_file "$INPUT"
			;;
		save)
			save_changes
			;;
		pretty)
			check_file
			if [ "$?" -ne 0 ]; then
				continue
			fi

			output "`human_readable "$PARSED_STRING"`" NL
			;;
		output)
			check_file
			if [ "$?" -ne 0 ]; then
				continue
			fi

			output "$PARSED_STRING" NL
			;;

		range\ *|read\ *|edit\ *|delete\ *|flatten\ *)
			range_ops "$INPUT"
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
				refresh
			else
				echo "(*) Nothing to undo."
			fi
			;;
		redo)
			if ! [ -z "$REDO_KEEP" ]; then
				UNDO_KEEP="$FILE_CONTENTS"
				FILE_CONTENTS="$REDO_KEEP"
				REDO_KEEP=""
				refresh
			else
				echo "(*) Nothing to redo."
			fi
			;;
		quit|exit)
			try_quit && break
			;;
		*)
			if ! [ -z "$INPUT" ]; then
				echo "(!) Unknown command: $INPUT. Try help."
			fi
			;;
	esac

done

exit 0
