#!/bin/bash -eu

# Given _tags array input, and a goal function, print a list of functions that pre: and post: tags imply should be called.
#
# E.g. given:
# 
#  declare -A _tags=([sudo]="pre:*" [devbox]="pre:* pre:sudo" [foo]=" pre:bar" [cleanup]=" post:*")
#
#  and goal: backup
#
# emits dependencies to stdout:
#
#   devbox
#   sudo
#   backup
#   cleanup
#
function_with_tag_dependencies() {

	declare -n tags="$1"
	local func="$2"
	declare -A deps=()

	#log() { echo >&2 "		 $*"; }

	# Given _tags input:
	#		 declare -A _tags=([sudo]="pre:*" [devbox]="pre:* pre:sudo" [foo]=" pre:bar" [cleanup]=" post:*")
	#
	# emits dependencies to stdout:
	#
	# * cleanup
	# devbox *
	# devbox sudo
	# foo bar
	# sudo *
	#
	function_dependencies() {
		local allfuncs=("${!tags[@]}")
		for func in "${allfuncs[@]}"; do
			for tag in ${tags[$func]}; do
				local referent
				if [[ $tag =~ ^pre:(.+) ]]; then
					referent="${BASH_REMATCH[1]}" 
					#log "$func before $referent"
					echo "$func before $referent"
				elif [[ $tag =~ ^post:(.+) ]]; then
					referent="${BASH_REMATCH[1]}" 
					#log "$func after $referent"
					echo "$func after $referent"
				fi
			done
		done
	}

	# Move lines with wildcards
	wildcard_dependencies_last() { awk '{ print ($0 ~ /\*/ ? "1" : "0") "\t" $0 }' | sort | cut -f2-; }

	expand_dependencies() {
		local func="$1"
		while read -r a relation b; do
			if [[ $a = '*' ]]; then
				#log "Expanding $a $b"
				for f in "${!_tags[@]}" $func; do
					echo "$f $relation $b"
				done
			elif [[ $b = '*' ]]; then
				#log "Expanding $a $b"
				for f in "${!_tags[@]}" $func; do
					echo "$a $relation $f"
				done
			else
				#log "Unaltered $a $b"
				echo "$a $relation $b"
			fi
		done

			# Expand in the context of 'backup':
			#
			# devbox sudo
			# devbox {devbox sudo backup}
			# sudo {devbox sudo backup}
			# foo bar
			# {devbox sudo backup} cleanup
			#

		}
	simplify_dependencies() {
		# Simplify, with top rules taking precedence in impossible situations:
		#
		# E.g input:
		#
		# cleanup cleanup
		# sudo cleanup
		# foo cleanup
		# devbox cleanup
		# backup cleanup
		# sudo cleanup
		# sudo sudo
		# sudo foo
		# sudo devbox
		# sudo backup
		# foo bar
		# devbox cleanup
		# devbox sudo
		# devbox foo
		# devbox devbox
		# devbox backup
		# devbox sudo
		#
		# Output:
		#
		# sudo cleanup
		# foo cleanup
		# devbox cleanup
		# backup cleanup
		# sudo foo
		# sudo devbox
		# sudo backup
		# foo bar
		# devbox foo
		# devbox backup
		#
		#
		declare -A seen=()
		
		while read -r a relation b; do
			#log "Considering '$a' '$b'"
			if [[ $a == "$b" ]]; then #log "  Dup: $a $b";
				continue;
			elif [[ -v seen["$a:$relation:$b"] ]]; then  #log "  Already seen $a $b";
				continue;
			elif [[ -v seen["$b:$relation:$a"] ]]; then  #log "  Seen inverse of $a $b";
				continue;
			else
				seen["$a:$relation:$b"]=1
				echo "$a $relation $b"
			fi

		done
	}


	# populate predecessors and successors
	set_predecessors_and_successors_of_invokedfunc() {
		local allfuncs=("${!tags[@]}")
		for func in "${allfuncs[@]}"; do
			for tag in ${tags[$func]}; do
				local referent

				if [[ $tag =~ ^pre:(.+) ]]; then
					referent="${BASH_REMATCH[1]}" 
					log "$func before $referent"
					deps[$referent]+=" $func"
				elif [[ $tag =~ ^post:(.+) ]]; then
					referent="${BASH_REMATCH[1]}" 
					log "$func after $referent"
					deps[$func]+=" $referent"
				fi

			done
		done
	}

			# We now have:
			#
			# devbox sudo
			# devbox *
			# sudo *
			# foo bar
			# * cleanup
			#
			# Expand in the context of 'backup':
			#
			# devbox sudo
			# devbox {devbox sudo backup}
			# sudo {devbox sudo backup}
			# foo bar
			# {devbox sudo backup} cleanup
			#
			# Becomes:
			#
			# devbox sudo
			# devbox devbox
			# devbox sudo
			# devbox backup
			# sudo devbox
			# sudo sudo
			# sudo backup
			# foo bar
			# devbox cleanup
			# sudo cleanup
			# backup cleanup
			#
			# Simplify, with top rules taking precedence in impossible situations:
			#
			# devbox sudo
			# devbox backup
			# sudo backup
			# foo bar
			# devbox cleanup
			# sudo cleanup
			# backup cleanup
			#
			# DFS on 'backup' to get successors:
			# backup cleanup
			#
			#
			# To get predecessors, invert:
			#
			# sudo devbox
			# backup devbox
			# backup sudo
			# bar foo
			# cleanup devbox
			# cleanup sudo
			# cleanup backup
			#
			# then DFS on 'backup':
			# devbox sudo backup
		

	# Traverse $1 (either predecessors or successors) to find links of $1
	resolve_deps() { 
		declare -A visited=()
		resolve() {
			declare -n graph="$1"   # Name reference to the graph (associative array)
			#declare -p "${!graph}"
			local node="$2"
			[[ -v visited[$node] ]] && return  # Already visited
			#log "Resolving $1 of $node"
			visited[$node]=1

			# declare -A predecessors=([sudo]=" devbox" ["*"]="devbox sudo" )
		
			# Safely expand dependencies (default to empty if unset)
			local deps="${graph[$node]-}"
			#log "$node has $1: $deps"
			#declare -p ${!graph}
			for dep in $deps; do
				[[ $dep != "$node" ]] || continue
				resolve "$1" "$dep"
			done
			echo "$node"
		}
		resolve "$@"
	}

	removefirst() { tail -n +2; }

	print_dependencies() {
		declare -gA predecessors=()
		declare -gA successors=()
		while read -r a relation b; do
			case "$relation" in
				before) predecessors[$b]+=" $a";;
				after) successors[$b]+=" $a";;
			esac
		done
		resolve_deps predecessors "$1"
		#echo ---
		resolve_deps successors "$1" | tac | removefirst
	}

	#set_predecessors_and_successors_of_invokedfunc
	function_dependencies | wildcard_dependencies_last |  expand_dependencies "$func"  | simplify_dependencies  | print_dependencies "$func"
}


# Set a string variable for each tag, with value being a space-separated list of tagged functions. 
# E.g. if we have _tags=([backup]="main" [sudo]="pre:*"), this function sets _tag_main="backup" and _tag_pre_STAR="sudo". I.e. _tags is inverted.
# Plugins can then evaluate _tag_foo to see how they apply to them e.g. systemd reads $_tag_execstart to find the @execstart-tagged function.
__expand_tags() {
	local taggedfunc tag safe_tag
	for taggedfunc in "${!_tags[@]}"; do
		for tag in ${_tags[$taggedfunc]}; do    # Expand space-separated tags
			#echo "Considering tag $tag on function $taggedfunc"
			# Convert invalid characters in tag names to valid variable names
			safe_tag="${tag//\!/BANG}"				# E.g. pre!:* becomes pre_BANG_STAR
			safe_tag="${safe_tag//\*/STAR}"				# E.g. pre:* becomes pre_STAR
			safe_tag="_tag_${safe_tag//[^a-zA-Z_]/_}"	# Make bash-safe varname out of $tag, e.g. '@pre:install' gets var '_tag_pre_install'
			# Create var dynamically. More than one function might be tagged, but typically there will be just one (e.g. @main or @execstart). We could like to reference these via $_main or $_execstart, not ${_main[0]} and ${_execstart[0]}, because envsubt, used in parser.bash to replace parametrized variables, can't handle arrays, so even though '$execstart' would expand to the first string in bash, it won't in envsubst. Hence the space-separated values here.
			# Note we don't export (declare -x) _tag_*, because when @sudo triggers a rerun of the function, we don't want it inheriting our (non-sudo) _tag_*. Because tags are appended, the child _tag_sudo gets a value like 'mount mount'.
			if [[ -v $safe_tag ]]; then
				declare -g "$safe_tag"="${!safe_tag} $taggedfunc"
			else
				declare -g "$safe_tag"="$taggedfunc"
			fi
			#echo "Declared $safe_tag = ${!safe_tag}"
		done
	done
}

