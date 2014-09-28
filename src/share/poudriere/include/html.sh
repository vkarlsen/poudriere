#!/bin/sh
# 
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

start_html_json() {
	json_main &
	JSON_PID=$!
}

stress_snapshot() {
	local AWK1='/\// {sum+=$2; X+=$3} END {printf "%1.2f%%\n", X*100/sum}'
	local SLOAD=$(sysctl vm.loadavg | awk '{ print $3 }')
	local SSWAP=$(swapinfo -k | awk "${AWK1}")
	local ahora=$(date "+%s")
	local EPOCH=$(bget epoch 2>/dev/null || echo 0)
	local SELAPSED="--"
	local elapsed
	local elhr
	if [ "${EPOCH}" != "0" ]; then
		elapsed=$((ahora-EPOCH))
		elhr=$((elapsed/3600))
		SELAPSED=$(date -j -u -r ${elapsed} "+${elhr}:%M:%S")
	fi
	bset stats_load "${SLOAD}"
	bset stats_swapinfo "${SSWAP}"
	bset stats_elapsed "${SELAPSED}"
}

json_main() {
	while :; do
		stress_snapshot
		update_stats || :
		build_json
		sleep 5
	done
}

build_json() {
	local log

	_log_path log
	local awklist=$(find $log -name ".poudriere.ports.*" \
		-o -name ".poudriere.stat*" \
		-o -name ".poudriere.setname" \
		-o -name ".poudriere.ptname" \
		-o -name ".poudriere.jailname" \
		-o -name ".poudriere.mastername" \
		-o -name ".poudriere.builders" \
		-o -name ".poudriere.buildname")
	awk -v now=$(date +%s) \
		-f ${AWKPREFIX}/json.awk ${awklist} | \
		awk 'ORS=""; {print}' | \
		sed  -e 's/,\([]}]\)/\1/g' \
		> ${log}/.data.json.tmp
	mv -f ${log}/.data.json.tmp ${log}/.data.json

	# Build mini json for stats
	awk -v mini=yes \
		-f ${AWKPREFIX}/json.awk ${awklist} | \
		awk 'ORS=""; {print}' | \
		sed  -e 's/,\([]}]\)/\1/g' \
		> ${log}/.data.mini.json.tmp
	mv -f ${log}/.data.mini.json.tmp ${log}/.data.mini.json
}

stop_html_json() {
	local log have_lock

	_log_path log
	if [ -n "${JSON_PID}" ]; then
		# First acquire the update_stats lock to ensure the process
		# doesn't get killed while holding it
		have_lock=0
		lock_acquire update_stats && have_lock=1

		kill ${JSON_PID} 2>/dev/null || :
		_wait ${JSON_PID} 2>/dev/null 1>&2 || :
		unset JSON_PID

		if [ ${have_lock} -eq 1 ]; then
			lock_release update_stats || :
		fi
	fi
	build_all_json 2>/dev/null || :
	rm -f ${log}/.data.json.tmp ${log}/.data.mini.json.tmp 2>/dev/null || :
}
