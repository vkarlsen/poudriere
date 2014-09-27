#!/bin/sh
# 
# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2014 Bryan Drewery <bdrewery@FreeBSD.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

usage() {
	[ $# -gt 0 ] && echo "Missing: $@" >&2
	cat << EOF
poudriere jail [parameters] [options]

Parameters:
    -c            -- Create a jail
    -d            -- Delete a jail
    -i            -- Show information about a jail
    -l            -- List all available jails
    -s            -- Start a jail (chroot)
    -u            -- Update a jail
    -r newname    -- Rename a jail

Options:
    -q            -- Quiet (Do not print the header)
    -n            -- Print only jail name (for use with -l)
    -J n          -- Run buildworld in parallel with n jobs.
    -j jailname   -- Specify the jailname
    -v version    -- Specify which version of DragonFly we want in jail
		      e.g. "3.6", "3.8", or "master"
    -M mountpoint -- Mountpoint
    -Q quickworld -- when used with -u jail is incrementally updated
    -m method     -- when used with -c forces the method to use by default
                     "git" to build world from source.  There are no other
                     method options at this time.
    -P patch      -- Specify a patch to apply to the source before building.
    -t version    -- Version of DragonFly to upgrade the jail to.

Options for -s:
    -p tree       -- Specify which ports tree the jail to start/stop with.
    -z set        -- Specify which SET the jail to start/stop with.
EOF
	exit 1
}

list_jail() {
	local format
	local j name version arch method mnt mntx hack

	format='%%-20s %%-13s %%-17s %%-7s %%-7s %%s'
	display_setup "${format}" 6 "-d -k2,2 -k3,3 -k1,1"
	if [ ${NAMEONLY} -eq 0 ]; then
		display_add "JAILNAME" "VERSION" "LAST-UPDATED" "ARCH" "METHOD" "PATH"
	else
		display_add JAILNAME
	fi
	[ -d ${POUDRIERED}/jails ] || return 0
	for j in $(find ${POUDRIERED}/jails -type d -maxdepth 1 -mindepth 1 -print); do
		name=${j##*/}
		if [ ${NAMEONLY} -eq 0 ]; then
			_jget version ${name} version
			_jget arch ${name} arch
			_jget method ${name} method
			-jget hack ${name} timestamp
			_jget mntx ${name} mnt
			case ${mntx} in
			    ${BASEFS}/*)
				mnt=BASEFS${mntx#${BASEFS}}
				;;
			    *)
				mnt=${mntx}
				;;
			esac
			display_add "${name}" "${version}" "${hack}" \
			    "${arch}" "${method}" "${mnt}"
		else
			display_add ${name}
		fi
	done
	[ ${QUIET} -eq 1 ] && quiet="-q"
	display_output ${quiet}
}

cleanup_new_jail() {
	msg "Error while creating jail, cleaning up." >&2
	delete_jail
}

# Lookup new version from newvers and set in jset version
update_version() {
	local version_extra="$1"

	eval `grep "^[RB][A-Z]*=" ${SRC_BASE}/sys/conf/newvers.sh `
	RELEASE=${REVISION}-${BRANCH}
	[ -n "${version_extra}" ] &&
	    RELEASE="${RELEASE} ${version_extra}"
	jset ${JAILNAME} version "${RELEASE}"
	echo "${RELEASE}"
}

rename_jail() {
	local cache_dir

	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	msg_n "Renaming '${JAILNAME}' in '${NEWJAILNAME}'"
	mv ${POUDRIERED}/jails/${JAILNAME} ${POUDRIERED}/jails/${NEWJAILNAME}
	cache_dir="${POUDRIERE_DATA}/cache/${JAILNAME}-*"
	rm -rf ${cache_dir} >/dev/null 2>&1 || :
	echo " done"
	msg_warn "The packages, logs and filesystems have not been renamed."
	msg_warn "If you choose to rename the filesystem then modify the 'mnt' and 'fs' files in ${POUDRIERED}/jails/${NEWJAILNAME}"
}

info_jail() {
	local nbb nbf nbi nbq nbs tobuild
	local building_started status log
	local elapsed elapsed_days elapsed_hms elapsed_timestamp
	local now start_time timestamp
	local jversion jarch jmethod pmethod

	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"

	POUDRIERE_BUILD_TYPE=bulk
	BUILDNAME=latest

	_log_path log
	now=$(date +%s)

	_bget status status 2>/dev/null || :
	_bget nbq stats_queued 2>/dev/null || nbq=0
	_bget nbb stats_built 2>/dev/null || nbb=0
	_bget nbf stats_failed 2>/dev/null || nbf=0
	_bget nbi stats_ignored 2>/dev/null || nbi=0
	_bget nbs stats_skipped 2>/dev/null || nbs=0
	tobuild=$((nbq - nbb - nbf - nbi - nbs))

	_jget jversion ${JAILNAME} version
	_jget jarch ${JAILNAME} arch
	_jget jmethod ${JAILNAME} method
	_jget timestamp ${JAILNAME} timestamp 2>/dev/null || :

	echo "Jail name:         ${JAILNAME}"
	echo "Jail version:      ${jversion}"
	echo "Jail arch:         ${jarch}"
	echo "Jail method:       ${jmethod}"
	if [ -n "${timestamp}" ]; then
		echo "Jail updated:      $(date -j -r ${timestamp} "+%Y-%m-%d %H:%M:%S")"
	fi
	if porttree_exists ${PTNAME}; then
		_pget pmethod ${PTNAME} method
		echo "Tree name:         ${PTNAME}"
		echo "Tree method:       ${pmethod:--}"
#		echo "Tree updated:      $(pget ${PTNAME} timestamp)"
		echo "Status:            ${status}"
		if calculate_elapsed_from_log ${now} ${log}; then
			start_time=${_start_time}
			elapsed=${_elapsed_time}
			building_started=$(date -j -r ${start_time} "+%Y-%m-%d %H:%M:%S")
			elapsed_days=$((elapsed/86400))
			calculate_duration elapsed_hms "${elapsed}"
			case ${elapsed_days} in
				0) elapsed_timestamp="${elapsed_hms}" ;;
				1) elapsed_timestamp="1 day, ${elapsed_hms}" ;;
				*) elapsed_timestamp="${elapsed_days} days, ${elapsed_hms}" ;;
			esac
			echo "Building started:  ${building_started}"
			echo "Elapsed time:      ${elapsed_timestamp}"
			echo "Packages built:    ${nbb}"
			echo "Packages failed:   ${nbf}"
			echo "Packages ignored:  ${nbi}"
			echo "Packages skipped:  ${nbs}"
			echo "Packages total:    ${nbq}"
			echo "Packages left:     ${tobuild}"
		fi
	fi

	unset POUDRIERE_BUILD_TYPE
}


check_emulation() {
	#do nothing on DragonFly
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
. ${SCRIPTPREFIX}/jail.sh.${BSDPLATFORM}

get_host_arch ARCH
REALARCH=${ARCH}
START=0
STOP=0
LIST=0
DELETE=0
CREATE=0
RENAME=0
QUIET=0
NAMEONLY=0
INFO=0
UPDATE=0
QUICK=0
METHOD=git
PTNAME=default
SETNAME=""

while getopts "iJ:j:v:z:m:n:M:sdlqcip:r:ut:z:P:Q" FLAG; do
	case "${FLAG}" in
		i)
			INFO=1
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		J)
			PARALLEL_JOBS=${OPTARG}
			;;
		v)
			VERSION=${OPTARG}
			;;
		a)
			# Option masked on DF
			ARCH=${OPTARG}
			# If TARGET=TARGET_ARCH trim it away and just use
			# TARGET_ARCH
			[ "${ARCH%.*}" = "${ARCH#*.}" ] && ARCH="${ARCH#*.}"
			;;
		m)
			METHOD=${OPTARG}
			;;
		n)
			NAMEONLY=1
			;;
		f)
			# Option masked on DF
			JAILFS=${OPTARG}
			;;
		M)
			JAILMNT=${OPTARG}
			;;
		Q)
			QUICK=1
			;;
		s)
			START=1
			;;
		k)
			# Option masked on DF
			STOP=1
			;;
		l)
			LIST=1
			;;
		c)
			CREATE=1
			;;
		d)
			DELETE=1
			;;
		p)
			PTNAME=${OPTARG}
			;;
		P)
			[ -f ${OPTARG} ] || err 1 "No such patch"
			SRCPATCHFILE=${OPTARG}
			;;
		q)
			QUIET=1
			;;
		u)
			UPDATE=1
			;;
		r)
			RENAME=1;
			NEWJAILNAME=${OPTARG}
			;;
		t)
			TORELEASE=${OPTARG}
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
			;;
		*)
			usage
			;;
	esac
done

saved_argv="$@"
shift $((OPTIND-1))

METHOD=${METHOD:-ftp}
if [ -n "${JAILNAME}" -a ${CREATE} -eq 0 ]; then
	_jget ARCH ${JAILNAME} arch 2>/dev/null || :
	_jget JAILFS ${JAILNAME} fs 2>/dev/null || :
	_jget JAILMNT ${JAILNAME} mnt 2>/dev/null || :
fi

check_jobs
case "${CREATE}${INFO}${LIST}${STOP}${START}${DELETE}${UPDATE}${RENAME}" in
	10000000)
		test -z ${JAILNAME} && usage JAILNAME
		test -z ${VERSION} && usage VERSION
		jail_exists ${JAILNAME} && \
		    err 2 "The jail ${JAILNAME} already exists"
		check_emulation
		maybe_run_queued "${saved_argv}"
		create_jail
		;;
	01000000)
		test -z ${JAILNAME} && usage JAILNAME
		export MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		_mastermnt MASTERMNT
		export MASTERMNT
		info_jail
		;;
	00100000)
		list_jail
		;;
	00010000)
		# -k stop option not supported on DF
		;;
	00001000)
		export SET_STATUS_ON_START=0
		test -z ${JAILNAME} && usage JAILNAME
		porttree_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
		maybe_run_queued "${saved_argv}"
		start_a_jail
		;;
	00000100)
		test -z ${JAILNAME} && usage JAILNAME
		maybe_run_queued "${saved_argv}"
		delete_jail
		;;
	00000010)
		test -z ${JAILNAME} && usage JAILNAME
		jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
		maybe_run_queued "${saved_argv}"
		jail_runs ${JAILNAME} && \
		    err 1 "Unable to update jail ${JAILNAME}: it is running"
		check_emulation
		update_jail ${QUICK}
		;;
	00000001)
		test -z ${JAILNAME} && usage JAILNAME
		maybe_run_queued "${saved_argv}"
		rename_jail
		;;
	*)
		usage
		;;
esac
