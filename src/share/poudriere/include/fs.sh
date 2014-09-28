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

createfs() {
	[ $# -ne 3 ] && eargs createfs name mnt fs
	local mnt
	mnt=$(echo $2 | sed -e "s,//,/,g")

	mkdir -p ${mnt}
}

do_clone() {
	cpdup -i0 -x "${1}" "${2}"
}

rollbackfs() {
	[ $# -ne 2 ] && eargs rollbackfs name mnt
	echo "The rollbackfs function is not used in DragonFly"
}

umountfs() {
	[ $# -lt 1 ] && eargs umountfs mnt childonly
	echo "The umountfs function is not used in DragonFly"

	return 0
}

zfs_getfs() {
	[ $# -ne 1 ] && eargs zfs_getfs mnt
	# The ZFS is never used in DragonFly
}

mnt_tmpfs() {
	[ $# -lt 2 ] && eargs mnt_tmpfs type dst
	echo "The mnt_tmpfs function is not used in DragonFly"
}

clonefs() {
	[ $# -lt 2 ] && eargs clonefs from to snap
	echo "The clonefs function is not used in DragonFly"
}

destroyfs() {
	[ $# -ne 2 ] && eargs destroyfs name type
	local mnt
	mnt=$1
	[ -d ${mnt} ] || return 0

	mnt=$(realpath ${mnt})
	chflags -R noschg ${mnt}
	rm -rf ${mnt}
}
