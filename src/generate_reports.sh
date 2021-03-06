#!/bin/bash

## The script writes the result of compilation and execution to a a
## file named after the username of the student being graded in root
## of his cloned directory. The script groups failed to compile
## submissions in $ROOT/p<i>/failed. A list of student names with repo
## names not in the right form are listed in
## $ROOT/c343-invalid.txt. These need to be graded manually because
## the script can not infer their repo name.

# set -euo pipefail

# the submission deadline
DATE='Sep 8 2017 11:59 am'
# lab = 0, homework = 1, project = 2
SUBMISSION_TYPE=0
SUBMISSION_INDEX=3
GRADEBOOK_PATH="students.csv"
# number of seconds to time out
ts=120

## -------------------------------------------------------------------

if [ "$SUBMISSION_TYPE" -eq 0 ]
then
    SUBMISSION_TYPE_I="lab"
elif [ "$SUBMISSION_TYPE" -eq 1 ]
then
    SUBMISSION_TYPE_I="homework"
else
    echo "bad SUBMISSION_TYPE val: " "$SUBMISSION_TYPE"
    exit -1
fi

#ROOT="/Users/dalmahal-admin/gradespace"
ROOT="/app"
#PROJDIR="${ROOT}/${SUBMISSION_TYPE_I}${SUBMISSION_INDEX}"
PROJDIR="${ROOT}/gradespace"

# path to the exported csv file from the gradebook on Canvas
DATAFILE="${ROOT}/${GRADEBOOK_PATH}"

# path to the required JARs, such as junit
CLASSPATH="$ROOT"

# path to the textfile that has a list of all students with compiling submissions
REPORTFILE="${PROJDIR}/reports.txt"

# path to the directory of compiling submissions
CLONESDIR="${PROJDIR}/clones"

# path to the textfile that has a list of students with not compiling submissions
ZEROSTUDENTSFILE="${PROJDIR}/failed.txt"

# path to the directory of not compiling submissions
FAILEDDIR="${PROJDIR}/failed/"

# path to the directory of missing submissions
MISSINGDIR="${PROJDIR}/missing/"

# path to the textfile that has a list of students who did not submit before the due date
LATESTUDENTSFILE="${PROJDIR}/late.txt"

# path to the repositories that does not have submissions
LATESTUDENTSDIR="${PROJDIR}/late"

# path to the textfile that contains a list of students who does not have a proper repository name
INVALIDFILE="${ROOT}/c343-invalid.txt"

rm -rf "$REPORTFILE" "$ZEROSTUDENTSFILE" "$FAILEDDIR" "$MISSINGDIR" "$CLONESDIR" "$LATESTUDENTSFILE" "$LATESTUDENTSDIR" "$INVALIDFILE"
mkdir -p "$FAILEDDIR" "$CLONESDIR" "$MISSINGDIR"

_SILENT_JAVA_OPTIONS="$_JAVA_OPTIONS"
unset _JAVA_OPTIONS
alias java='java "$_SILENT_JAVA_OPTIONS"'

read_csv_field ()
{
    local student="$1";shift
    local ind="$1";    shift
    sed -E 's/("[^",]+),([^",]+")/\1###\2/g' "$DATAFILE" | awk -v v=$ind -v u=$student -F, '$3 == u {print $v}' | sed 's/###/,/g';
}

# submission_type: 0 is lab, 1 is homework, 2 is project
function get_main_class_paths ()
{
    local submission_type="$1"; shift
    local submission_index="$1"; shift
    local student_dir="$1"; shift

    local type_pattern=""
    
    if [ "$submission_type" -eq 0 ]
    then
	type_pattern="lab"
    elif [ "$submission_type" -eq 1 ]
    then
	type_pattern="hw\|homework\|hmwrk\|assignment\|assign\|ass"
    else
	echo "bad submission_type val: " "$submission_type"
	exit -1
    fi
    RETURN=($(grep -rnw "$student_dir" -l -e "public static void main" | grep -i "${type_pattern}.*${submission_index}.*.java"))
}

function main ()
{
    # add the github ssh key to the keychain to remember it.
    keychain id_rsa
    . ~/.keychain/`uname -n`-sh
    
    s=($(cut -d, -f4 "$DATAFILE" | sed 1,2d | awk -F= '{print $1}'))

    for i in "${s[@]}"; do
	cd "$CLONESDIR"
	fullname=$(read_csv_field $i 1)
	echo "checking ${i},${fullname}"
	repo="git@github.iu.edu:H343-Fall2017/H343$i.git"
	git ls-remote "$repo" -q > /dev/null 2>&1
	if [ $? = "0" ]; then
	    git clone "$repo" "$i" -q > /dev/null 2>&1
	    cd "$i";
	    # checkout the last commit before the due date
	    git checkout `git rev-list -1 --before="$DATE" master` -q > /dev/null 2>&1
	    echo $i,"$fullname" >> "$REPORTFILE"
	    printf "$i,${fullname}" > "${CLONESDIR}/${i}/${i}.txt"
	    # rename all directories with spaces to underscores
	    find -name "* *" -print0 | sort -rz | \
		while read -d $'\0' f; do mv -v "$f" "$(dirname "$f")/$(basename "${f// /_}")"; done
	    get_main_class_paths "$SUBMISSION_TYPE" "$SUBMISSION_INDEX" "${CLONESDIR}/${i}"
	    local failed_flag=0
	    local missing_flag=1
	    for main_class_path in "${RETURN[@]}"; do
		missing_flag=0
		srcpath=$(dirname "$main_class_path")
		main_class_file_name=$(basename "$main_class_path");main_class_file_name_no_ext=${main_class_file_name%.*}
		cd "$srcpath"
		# remove the package line in the source files if exists
		sed -i.bak '/package .*;/d' *.java
		sleep 1
		printf "\n\n--------------------------------------------------------\n\nCompilation output for ${main_class_path}\n\n" >> "${CLONESDIR}/${i}/${i}.txt"
		javac *.java >> "${CLONESDIR}/${i}/${i}.txt" 2>&1
		if [ $? = "0" ]; then
		    # submission compiles? great! let's check what you got
		    printf "\n\n--------------------------------------------------------\n\nRun-time output for ${main_class_path} output\n\n" >> "${CLONESDIR}/${i}/${i}.txt" 
		    timeout -s KILL ${ts}s java -cp . "$main_class_file_name_no_ext" >> "${CLONESDIR}/${i}/${i}.txt" 2>&1
		else
		    failed_flag=1
		fi
	    done
	    if [ "$failed_flag" -eq 1 ]; then
	    	# submission does not compile? well, too bad!
		echo $i,"$fullname" >> "$ZEROSTUDENTSFILE"
		cd "$CLONESDIR"
		mv "${CLONESDIR}/${i}" "${FAILEDDIR}/"
	    fi
	    if [ "$missing_flag" -eq 1 ]; then
		echo $i,"$fullname" >> "$ZEROSTUDENTSFILE"
		cd "$CLONESDIR"
		mv "${CLONESDIR}/${i}" "${MISSINGDIR}/"
	    fi
	else
	    echo $i,"$fullname" >> "$INVALIDFILE"
	fi
    done
}

main "$@"
