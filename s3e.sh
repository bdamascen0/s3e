#!/bin/bash
# s3e.sh
# Simple Syscall Signature Emulator
# version 4.6
# Copyright (c) 2022 Bruno Damasceno <bdamasceno@hotmail.com.br>


# Description:
# This program is a simple system call signature emulator script with:
# -integrated system call signature emulation to provide some inode-eviction analysis for the linux kernel
# -integrated ramdisk setup, formatting, mounting and reseting.
# -integrated folder layout setup.
# -integrated safety checks.
# -integrated populate, test and measurements functions.


# Disclaimer:
# I'm no expert so please forgive any technical inaccurancy in this document.


# - About this work -
#
# This work is about a severely degraded performance found during rpm operations with specific packages on openSUSE Tumbleweed.
# More specifically, the issue happens with the 5.15 LTS kernel on a btrfs partition with btrfs compression property enabled at the target folder.
# A bug [1] was filled on openSUSE but the root cause wasn't found and it was considered a kernel regression outside the btrfs code.
# The bug was later cross-referenced on a kernel patchset for btrfs [2] where Filipe Manana gave it the following description:
# "The issue was caused indirectly due to an excessive number of inode evictions on a 5.15 kernel, about 100x more compared to a 5.13, 5.14 or a 5.16-rc8 kernel."
# The patchset also provided a script that mimics a portion of the rpm operations to test the btrfs improvements and it got me thinking if the regression could be triggered without rpm itself.
# I saw it as a great opportunity since my original reproduction instructions [3] were absolutely tied to the opensuse environment.
# It didn't work at first so I decided to use the strace results as a starting point with the objective to add the missing system calls to the script.
# After some ramdisk block device learning and some bash workout I got an easy testing setup for this syscall signature research.
# Add more kvm, bash and distro hours and I could also test newer 5.15 kernels from Zenwalk, Debian and Ubunt to make sure the situation hasn't changed.
# The main motivation for this development was to improve the regression reproduction and, as a bonus, I was rewarded by discovering the possible guilty syscall combination.
# I hope both achievements to be enough incentive to get it further investigated by kernel developers.
#
# [1] https://bugzilla.opensuse.org/show_bug.cgi?id=1193549
# [2] https://lore.kernel.org/linux-btrfs/285785ef66283fb6b00fe69112dc1240a2aa1e19.1642676248.git.fdmanana@suse.com/
# [3] https://lore.kernel.org/linux-fsdevel/MN2PR20MB251235DDB741CD46A9DD5FAAD24E9@MN2PR20MB2512.namprd20.prod.outlook.com/T/


# - The original system call signature -
#
# This program tries to replicate part of the syscall sequecence observed on some rpm operations that triggered the regression.
# Follow the original syscall signature sample captured with strace (single file excerpt):
#
# newfstatat(AT_FDCWD, "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz", {st_mode=S_IFREG|0644, st_size=7362, ...}, AT_SYMLINK_NOFOLLOW) = 0
# newfstatat(AT_FDCWD, "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE", 0x7ffd3a183a20, AT_SYMLINK_NOFOLLOW) = -1 ENOENT (No such file or directory)
# rename("/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz", "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE") = 0
# newfstatat(AT_FDCWD, "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE", {st_mode=S_IFREG|0644, st_size=7362, ...}, AT_SYMLINK_NOFOLLOW) = 0
# unlink("/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE") = 0
# umask(0577)                             = 022
# openat(AT_FDCWD, "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz", O_WRONLY|O_CREAT|O_EXCL|O_TRUNC, 0666) = 13
# fcntl(13, F_SETFD, FD_CLOEXEC)          = 0
# umask(022)                              = 0577
# write(13, "\37\213\10\0\0\0\0\0\0\3\265]ms\3338\222\376\274\371\25(WmU&76ER\324K"..., 7362) = 7362
# write(3, "'\0\0\0", 4)                  = 4
# write(3, "\n!zypp.proto.target.PackageProgr"..., 39) = 39
# close(13)


# - The "inode-eviction" system call signature -
#
# After testing several different combinations, the minimum theorical syscall signature to trigger the regression would be:
#
# rename("/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz", "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE") = 0
# unlink("/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE") = 0
# openat(AT_FDCWD, "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz", O_WRONLY|O_CREAT|O_EXCL|O_TRUNC, 0666) = 13
#
# This way, we should rename a file, unlink the renamed file and create a new file.
# The file existence check and the file content writing didn't demonstrated any first order impact.
# For simplification, the fcntl and close syscalls were considered consequences of openat for empty and non empty files.
# The umask changes weren't tested.
# Please note that this program can not provide a clean syscall sequence as the shell interpreter and the external programs executed by the script will generate their own system calls too.
# Another remark goes to the rename operation. While the rename program from util-linux generates a rename syscall, the mv program from coreutils generates a renameat2 syscall.
# Both were verified to trigger the regression and the major factor here is that the util-linux rename isn't easily availble on some distributions like Ubuntu.


# - Triggering the regression -
#
# Verify the dependencies and run this script on any 5.15 kernel.
# Tests 1 and 2 doesn't produce the minimum syscall signature and should be fast on all folders (uncompressed, zstd and lzo folders).
# Tests 3, 4 and 5 does produce the minimum syscall signature and should be fast on the uncompressed folder and a lot slower on the zstd and lzo folders.
#
# The slow results on tests 3, 4 and 5 are due:
# a_ the kernel regression: specific system calls touching files with btrfs compression property will generate higher inode eviction on 5.15 kernels.
# b_ the inode eviction generating btrfs inode logging and directory logging.
# c_ the btrfs directory logging on the 5.15 kernel not being particulary efficient in the presence of high inode eviction.
#
# There is already an ongoing work [1] to improve "c" on newer kernels but I was told they are not elegible for the 5.15 version due to backporting policy restrictions.
# AFAIK there isn't any work for "a" yet.
# The consequence is that btrfs users running the 5.15 kernel may experience severely degraded performance for specific I/O workloads on files with the compression property enabled.
#
# [1] https://bugzilla.opensuse.org/show_bug.cgi?id=1193549


# Main results (x86_64)
#
# __T E S T - 3 - populate + test. test renameat2/openat + unlinking syscalls w/ empty files (3x)
# opensuse leap 15.4 beta - kernel 5.14.21-150400.11 - (kvm)
# ...updating 250 files on /mnt/inode-ev/zstd:         Job took 811 milliseconds   @inode_evictions: 251
# ...updating 250 files on /mnt/inode-ev/lzo:          Job took 912 milliseconds   @inode_evictions: 251
# ...updating 250 files on /mnt/inode-ev/uncompressed: Job took 993 milliseconds   @inode_evictions: 251
# opensuse tumbleweed ----- kernel 5.16.14
# ...updating 250 files on /mnt/inode-ev/zstd:         Job took 1398 milliseconds  @inode_evictions: 250
# ...updating 250 files on /mnt/inode-ev/lzo:          Job took 1323 milliseconds  @inode_evictions: 250
# ...updating 250 files on /mnt/inode-ev/uncompressed: Job took 1365 milliseconds  @inode_evictions: 250
# opensuse tumbleweed ----- kernel 5.15.12
# ...updating 250 files on /mnt/inode-ev/zstd:         Job took 12500 milliseconds @inode_evictions: 31375
# ...updating 250 files on /mnt/inode-ev/lzo:          Job took 12327 milliseconds @inode_evictions: 31375
# ...updating 250 files on /mnt/inode-ev/uncompressed: Job took 1482 milliseconds  @inode_evictions: 499
# ubuntu jammy jellyfish -- kernel  5.15.0.23 (5.15.27) - (kvm) 
# ...updating 250 files on /mnt/inode-ev/zstd:         Job took 17521 milliseconds @inode_evictions: 31375
# ...updating 250 files on /mnt/inode-ev/lzo:          Job took 17114 milliseconds @inode_evictions: 31375
# ...updating 250 files on /mnt/inode-ev/uncompressed: Job took 1138 milliseconds  @inode_evictions: 499


# Load test results (x86_64):
#
# __T E S T - 3 - populate + test. test renameat2/openat + unlinking syscalls w/ empty files (3x)
# ubuntu jammy jellyfish -- kernel  5.15.0.23 (5.15.27) - (kvm) 
# 1000 files gives aprox. (103204/1999) 51.6 x more inode evictions and aprox. (139000/7688) 18.1 x more time
# 250  files gives aprox.   (31375/499) 62.9 x more inode evictions and aprox.  (17300/1138) 15.2 x more time
# 100  files gives aprox.    (5050/199) 25.4 x more inode evictions and aprox.    (1600/430)  3.7 x more time
# 50   files gives aprox.     (1275/99) 12.8 x more inode evictions and aprox.     (560/276)  2.0 x more time
# 10   files gives aprox.       (55/19)  2.8 x more inode evictions and aprox.      (115/85)  1.3 x more time


# CPU usage results:
# The regression causes significant CPU usage by the kernel.
#
# __T E S T - 3 - populate + test. test renameat2/openat + unlinking syscalls w/ empty files (3x)
# ubuntu jammy jellyfish -- kernel  5.15.0.23 (5.15.27) - (kvm) 
# ...updating 1000 files on /mnt/inode-ev/zstd:           Job took 137841 milliseconds
# real	2m17,881s
# user	0m1,704s
# sys	2m11,937s
# ...updating 1000 files on /mnt/inode-ev/lzo:            Job took 135456 milliseconds
# real	2m15,478s
# user	0m1,805s
# sys	2m9,758s
# ...updating 1000 files on /mnt/inode-ev/uncompressed:   Job took 7496 milliseconds
# real	0m7,517s
# user	0m1,386s
# sys	0m4,899s


# Test system specification:
# host cpu: AMD FX-8370E
# test storage medium: RAM disk block device
# opensuse tumbleweed           - host: 8 cores, 8GB RAM, SSD
# opensuse leap 15.4 beta (kvm) - host: 8 cores, 8GB RAM, SSD / guest: 2 cores, 2G RAM
# ubuntu jammy jellyfish  (kvm) - host: 8 cores, 8GB RAM, SSD / guest: 2 cores, 2G RAM


# Dependencies: modprobe, blockdev, mv, btrfs, xfs_io, compsize, grep, wc, which, kernel modules: brd*, btrfs.
# Optional dependencies: rename, bpftrace, time.
# Package names: kmod (modprobe), util-linux (blockdev, rename), coreutils (mv, wc), xfsprogs (xfs_io), btrfsprogs, compsize, which, bpftrace, time.
# Specific ubuntu package names: btrfs-progs, btrfs-compsize, debianutils (which).
# (*) kernels compiled with ramdisk option (like zenwalk) will need additional customization.


# Changelog:
# v4.6 20220320
#   first public version.
#   revised introduction text.
#   added system resource usage results.
#   code refactor:
#   -added basic integration for the time program (system resources usage).
#   -added time 2nd level external parameter.
#   -changed test_pre function.
#   -added basic file check for the time program
# v4.5 20220319 (internal)
#   added test results.
#   code refactor:
#   -added basic integration for the bpftrace program.
#   -added bpftrace 2nd level external parameter.
#   -changed test_pre and run_test functions.
#   -added basic file check for rename and bpftrace programs.
# v4.4 20220317 (internal)
#   code refactor:
#   -added system call control to make a unique syscall signature for each 3x test pack.
#   -simplified probe reporting logic.
#   -hardened fsetup logic.
#   -added initial rename test for reference.
#   -changed tests (syscall signature).
#   -added unified test description.
#   -moved populate out from test_pre function (populate_pre).
#   -added 2nd level external parameters: populate-only and test-only.
#   -turned off dynamic test progress indication with test-only parameter to decrease the strace log size.
#   -added qsetup external parameter.
#   -added qsetup and pre_populate functions.
#   fix pre_populate conditional.
#   added rename syscall.
#   added back xfs_io since it is used on the reference test.
#   fix var declaration: compress3 missing, compress1 declared twice.
#   update and cleanup of comments, usage and test descriptions.
#   tooling: external batch test script to get strace logs for all tests.
#   added introduction text.
# v4.3 20220221 (internal)
#   changed tests (file sizes).
# v4.2 20220216 (internal)
#   fix for distros missing /usr/sbin in %PATH.
#   removed xfs_io to simplify dependency.
# v4.1 20220212 (internal)
#   fix compression probe logic for reset.
#   fix reset by adding multiple probe calls.
# v4.0 20220212 (internal)
#   code refactor:
#   -added test_pre function to simplify test configuration.
#   changed tests (file sizes and entropy level).
#   fix sync logic to run before each single test from a 3x test pack.
# v3.0 20220212 (internal)
#   code refactor:
#   -added safety checks.
#   -added usage instructions.
#   -added external parameters for running one action for each run.
#   -added support for multiple 3x test pack.
#   -added functions probe, populate, run_test, fsetup and usage.
#   -added dynamic test progress indication.
#   tooling: external probe script to help with active debbuging.
# v2.0 20220201 (internal)
#   first version capable of triggering the regression.
#   code refactor:
#   -added function for setup/populate.
#   -added capability to populate with non empty files.
#   -increased test pack to 3x: zstd, lzo, none (three folders).
#   added unlink and openat syscalls.
# v1.0 20220129 (internal)
#   first functional version.
#   run-once script with integrated setup, reset, populate and 2x test pack: zstd, none (one folder).
#   added first syscalls (newfstatat and renameat2).


#add /usr/sbin to $PATH. needed for btrfs compsize modprobe and blockdev on debian
if [[ `echo \`env | grep PATH | grep sbin | wc -l\`` = 0 ]]; then
    env PATH=$PATH:/usr/sbin > /dev/null
fi

cmd1=disable
cmd2=disable
cmd3=disable
cmd4=disable
cmd5a=disable
cmd5b=disable
cmd6=disable
struct=missing
compress1=0
compress2=0
compress3=0
populate=disable
test=disable

test2=enable
populate2=enable
progress=enable
bpf=disable
timee=disable

dir1=zstd
dir2=lzo
dir3=uncompressed
DIR=zzz

dd_if=/dev/zero
dd_bs=1024 
dd_count=1
nfstatat=enable
ulnk=enable
ren=r-at2
NUM_FILES=250

DEV=/dev/ram0
MNT=/mnt/inode-ev
DIR_1="$MNT/$dir1"
DIR_2="$MNT/$dir2"
DIR_3="$MNT/$dir3"

dtest0="populate/test.          test renameat2/openat syscalls w/ empty files (zstd) - ref implementation based on fdmanana's script"
dtest1="unlink/populate + test. test renameat2/openat syscalls w/ empty files (3x = zstd, lzo, none)"
dtest2="unlink/populate + test. test renameat2/openat + newfstatat + write syscalls (non empty files, 3x)"
dtest3="populate + test.        test renameat2/openat + unlinking syscalls w/ empty files (3x)"
dtest4="populate + test.        test renameat2/openat + unlinking + newfstatat + write syscalls (non empty files, 3x)"
dtest5="populate + test.        test rename   /openat + unlinking + newfstatat + write syscalls (non empty files, 3x)"


probe() {
    echo "__P r o b e  $1"
    if [ -b $DEV ]
        then cmd1=disable && probe1=ok
        else cmd1=enable && probe1=missing; fi
    
    if [[ `echo \`blockdev --report $DEV | grep 524288000 | wc -l\`` = 1 ]]
        then cmd2=enable && probe2=ok
        else cmd2=disable && probe2=error; fi

    if [[ `echo \`btrfs device scan $DEV 2>&1 | grep ERROR: | wc -l\`` > 0 ]]
        then cmd3=disable && probe3=error
        else cmd3=enable && probe3=ok; fi
    
    if [[ -d $MNT ]]
        then cmd4=enable && probe4=ok
        else cmd4=disable && probe4=missing; fi
    
    if [[ `echo \`btrfs fi show $MNT 2>&1 | grep ERROR: | wc -l\`` > 0 ]]
        then cmd5a=disable && probe5a=error
        else cmd5a=enable && probe5a=ok; fi
        
    if [[ `echo \`btrfs fi show $MNT | grep -E "inode-ev|500.00MiB" | wc -l\`` > 1 ]]
        then cmd5b=enable && probe5b=ok
        else cmd5b=disable && probe5b=error; fi
    
    if [ -d $DIR_1 ] && [ -d $DIR_2 ] && [ -d $DIR_3 ] && [ -f $MNT/o.k ]
        then struct=ok
        else struct=missing; fi

    if [ $struct = ok ]
        then
            compress1=`echo \`btrfs property get $DIR_1 | grep "zstd:1" | wc -l\``
            compress2=`echo \`btrfs property get $DIR_2 | grep "lzo" | wc -l\``
            compress3=`echo \`btrfs property get $DIR_3 | wc -l\``            
            cmd6=enable && probe6a=ok
        else
            #updates the compression probe result during the reset command
            compress1=`echo \`btrfs property get $DIR_1 2> /dev/null | grep "zstd:1" | wc -l\``  
            compress2=`echo \`btrfs property get $DIR_2 2> /dev/null | grep "lzo" | wc -l\``
            compress3=`echo \`btrfs property get $DIR_3 2> /dev/null | wc -l\``
            cmd6=disable && probe6a=missing
    fi
    
    if [ $compress1 = 1 ] && [ $compress2 = 1 ] && [ $compress3 = 0 ]
        then populate=enable && test=enable && probe6b=ok
        else populate=disable && test=disable && probe6b=missing; fi
    
    if [ "$1" != quiet ]; then
        echo "! RAM disk device ............ ( $probe1 )"
        echo "! RAM disk size .............. ( $probe2 )"
        echo "! RAM disk Btrfs ............. ( $probe3 )"
        echo "! RAM disk mount point ....... ( $probe4 )"
        echo "! Mounted RAM disk ........... ( $probe5a )"
        echo "! Mounted RAM disk size ...... ( $probe5b )"
        echo "! Folder structure ........... ( $probe6a )"
        echo "! Folder compression ......... ( $probe6b )"
    fi
    }


setup() {
    echo "__S e t u p  $1"
    [ "$1" = 1 ] && [ $cmd1 = "enable" ] && modprobe brd rd_size=512000 max_part=1 rd_nr=1
    [ "$1" = 2 ] && [ $cmd2 = "enable" ] && mkfs.btrfs --label inode-ev --force $DEV > /dev/null
    [ "$1" = 3 ] && [ $cmd3 = "enable" ] && mkdir $MNT
    [ "$1" = 4 ] && [ $cmd4 = "enable" ] && mount $DEV $MNT
    [ "$1" = 5 ] && [ $cmd5a = "enable" ] && [ $cmd5b = "enable" ] && mkdir $MNT/{$dir1,$dir2,$dir3} && echo -n > $MNT/o.k
    if [ "$1" = 6 ] && [ $cmd6 = "enable" ]
        then
            btrfs property set $DIR_1 compression zstd:1
            btrfs property set $DIR_2 compression lzo
            btrfs property set $DIR_3 compression none; fi
    }


quick_setup() {
    for quick in 1 2 3 4 5 6; do
        probe "quiet"
        setup "$quick"; done
    }


force_setup() {
    echo "Warning!!! This option will disable all safety checks!!!"
    read -t 10 -n 1 -e -p "Do you want to proceed? (yes/no) " yn
    case $yn in
        "y" ) ;;
        "n" ) exit;;
        *   ) exit;;
    esac
    cmd1=enable; cmd2=enable; cmd3=enable; cmd4=enable; cmd5a=enable; cmd5b=enable; cmd6=enable
    for force in 1 2 3 4 5 6; do
        setup "$force"; done
    }


reset() {
    echo "__R e s e t"
    probe "quiet"
    if [ $cmd5b = "enable" ] && [ $cmd4 = "enable" ]; then
        umount $MNT
        probe "quiet"; fi
    if [ $cmd3 = "enable" ]; then
        rm --dir $MNT
        probe "quiet"; fi
    if [ $cmd2 = "enable" ]; then
        rmmod brd; fi
    probe
    }


populate() {
    DIR=$1
    echo "...populating 1st generation of files on $DIR:"
    for ((i = 1; i <= $NUM_FILES; i++)); do
        #enable turning the files empty again
        [ $dd_bs = 0 ] && [ -f $DIR/file_$i ] && unlink $DIR/file_$i
        #only keep 1st generation for compsize accuracy after 1st run (inaccurate if decreasing the number of files after 1st run)
        [ -f $DIR/file_$i-RPMDELETE ] && unlink $DIR/file_$i-RPMDELETE
        echo -n > $DIR/file_$i
        [ $dd_bs != 0 ] && dd if=$dd_if bs=$dd_bs count=$dd_count of=$DIR/file_$i status="none"
    done
    [ $dd_bs != 0 ] && compsize $DIR | grep -E "zstd|lzo|none"
    }


run_test() {
    DIR=$1
    sync
    xfs_io -c "fsync" $DIR
    echo -e "\n...updating $NUM_FILES files on $DIR:"
    #dumb pause so bpftrace has time to atach its probe
    [ $bpf = enable ] && sleep 3s
    start=$(date +%s%N)
    
    for ((i = 1; i <= $NUM_FILES; i++)); do
        if [ $nfstatat = enable ]
            then
                if [ -f $DIR/file_$i ] && [ ! -f $DIR/file_$i-RPMDELETE ]
                    then
                        #test2,4,5 // always satisfied by populate()
                        [ $ren = r-at2 ] && mv $DIR/file_$i $DIR/file_$i-RPMDELETE
                        [ $ren = r ] && rename $i $i-RPMDELETE $DIR/file_$i
                        if [ -f $DIR/file_$i-RPMDELETE ]
                            then
                                [ $ulnk = enable ] && unlink $DIR/file_$i-RPMDELETE
                        fi
                fi
            else
                #test1,3
                [ $ren = r-at2 ] && mv $DIR/file_$i $DIR/file_$i-RPMDELETE
                [ $ren = r ] && rename $i $i-RPMDELETE $DIR/file_$i
                [ $ulnk = enable ] && unlink $DIR/file_$i-RPMDELETE
        fi
        echo -n > $DIR/file_$i
        [ $dd_bs != 0 ] && dd if=$dd_if bs=$dd_bs count=$dd_count of=$DIR/file_$i status="none"
        if [ $progress = enable ]
            then
                echo -n "_$i"
                [ $i != $NUM_FILES ] && echo -ne "\r"
        fi
    done
    
    end=$(date +%s%N)
    dur=$(( (end - start) / 1000000 ))
    echo -ne "\r"
    echo "Job took $dur milliseconds"
    }


populate_pre() {
    probe "quiet"
    if [ $populate = "enable" ]; then
        echo "__P o p u l a t e"
        populate "$DIR_1"
        populate "$DIR_2"
        populate "$DIR_3"
    fi
    }


test_pre() {
    probe "quiet"
    if [ $test = "enable" ]
        then
            echo -n "__T E S T - $1 - "
            [ $1 = 1 ] && echo $dtest1
            [ $1 = 2 ] && echo $dtest2
            [ $1 = 3 ] && echo $dtest3
            [ $1 = 4 ] && echo $dtest4
            [ $1 = 5 ] && echo $dtest5
            [ $1 = 6 ] && echo $dtest6
            if [ $bpf = enable ]
                then
                    for dir in "$DIR_1" "$DIR_2" "$DIR_3"
                        do
                            bpftrace -e 'kprobe:btrfs_evict_inode { @inode_evictions = count(); }' & run_test "$dir"
                            pkill bpftrace
                            #dumb pause to wait the bpftrace report
                            sleep 2s
                        done
            fi
            if [ $timee = enable ]
                then
                    time run_test "$DIR_1"
                    time run_test "$DIR_2"
                    time run_test "$DIR_3"
            fi
            if [ $bpf = disable ] && [ $timee = disable ]
                then
                    run_test "$DIR_1"
                    run_test "$DIR_2"
                    run_test "$DIR_3"
            fi
    fi
    }


run_test_reference() {
    mkdir $MNT/testdir
    #added (prerequisite to trigger the kernel regression)
    btrfs property set $MNT/testdir compression zstd:1
    
    for ((i = 1; i <= $NUM_FILES; i++)); do
        echo -n > $MNT/testdir/file_$i
    done
    
    sync
    
    # Do some change to testdir and fsync it.
    echo -n > $MNT/testdir/file_$((NUM_FILES + 1))
    xfs_io -c "fsync" $MNT/testdir

    echo "Renaming $NUM_FILES files..."
    start=$(date +%s%N)
    for ((i = 1; i <= $NUM_FILES; i++)); do
        mv $MNT/testdir/file_$i $MNT/testdir/file_$i-RPMDELETE
    done
    end=$(date +%s%N)

    dur=$(( (end - start) / 1000000 ))
    echo "Renames took $dur milliseconds"
    }


usage() {
    echo "Simple Syscall Signature Emulator (s3e)"
    echo "Usage: ./s3e.sh [OPTIONS]"
    echo "--probe : safety checks evaluation"
    echo "--qsetup  : quick setup - run all setup steps from 1 to 6"
    echo "--setup 1 : create the RAM disk ($DEV)"
    echo "--setup 2 : format the RAM disk (Btrfs)"
    echo "--setup 3 : create the mount point ($MNT)"
    echo "--setup 4 : mount the RAM disk"
    echo "--setup 5 : create folder structure"
    echo "--setup 6 : set btrfs compression on folder structure"
    echo "--reset : umount and unload the RAM disk and exclude the mount point"
    echo "--test1 : $dtest1"
    echo "--test2 : $dtest2"
    echo "--test3 : $dtest3"
    echo "--test4 : $dtest4"
    echo "--test5 : $dtest5"
    echo "--test(x) --bpftrace : add inode evictions count for all 3x test packs"
    echo "--test(x) --time : add system resource usage for all 3x test packs"
    }


file_check_rename() {
    if [[ `echo \`rename --version | grep "util-linux" | wc -l\`` = 0 ]]
        then
            rename --version
            exit
    fi
    }

file_check_bpftrace() {
    if [[ `echo \`which bpftrace | grep "/bpftrace" | wc -l\`` = 0 ]]
        then
            bpftrace --version
            exit
    fi
    }

file_check_time() {
    if [[ `echo \`which time  | grep "/time" | wc -l\`` = 0 ]]
        then
            time
            exit
    fi
    }


case "$2" in
    "--time")
        file_check_time
        timee=enable;;
    "--bpftrace")
        file_check_bpftrace
        bpf=enable;;
    "--populate-only")
        test2=disable;;
    "--test-only")
        progress=disable
        populate2=disable;;
    *)
        ;;
esac


case "$1" in
    "--probe")
        probe;;
    "--setup")
        probe "quiet"
        setup "$2"
        probe;;
    "--qsetup")
        quick_setup
        probe;;
    "--fsetup")
        force_setup
        probe;;
    "--reset")
        reset;;
    "--test0")
        #non standard test (doesn't use internal functions).
        #2nd level external parameters have no effect.
        echo "__T E S T - 0 - $test0"
        probe "quiet"
        [ $test = "enable" ] && run_test_reference;;
    "--test1")
        dd_bs=0
        nfstatat=disable
        ulnk=disable
        [ $populate2 = "enable" ] && populate_pre "1"
        [ $test2 = "enable" ] && test_pre "1";;
    "--test2")
        dd_bs=1024
        nfstatat=enable
        ulnk=disable
        [ $populate2 = "enable" ] && populate_pre "2"
        [ $test2 = "enable" ] && test_pre "2";;
    "--test3")
        dd_bs=0
        nfstatat=disable
        ulnk=enable
        [ $populate2 = "enable" ] && populate_pre "3"
        [ $test2 = "enable" ] && test_pre "3";;
    "--test4")
        dd_bs=1024
        nfstatat=enable
        ulnk=enable
        [ $populate2 = "enable" ] && populate_pre "4"
        [ $test2 = "enable" ] && test_pre "4";;
    "--test5")
        file_check_rename
        dd_bs=1024
        nfstatat=enable
        ulnk=enable
        ren=r
        [ $populate2 = "enable" ] && populate_pre "5"
        [ $test2 = "enable" ] && test_pre "5";;
    "--test6")
        echo disabled
        exit
        #add your new shining custom test here :-)
        echo "__T E S T - 6 - custom"
        #dd_if=/dev/zero        #the kernel regression wasn't found to be affected by the higher entropy level of the files when using /dev/urandom (affects compression efficiency).
        #dd_bs=1024             #the kernel regression wasn't found to be affected by the write syscall and file sizes up tp 8Kb (medium file sizes of some rpm packages affected by the regression).
        #dd_count=1             #the kernel regression wasn't found to be affected by fragmenting the writing of each testing file.
        #nfstatat=enable        #the kernel regression wasn't found to be affected by the newfstatat syscall.
        #ulnk=enable            #the kernel regression is affected by the unlink syscall as it is part of the inode-eviction syscall signature.
        #NUM_FILES=1000         #1000 files gives aprox. (103204/1999) 51.6 x more inode evictions and aprox. (139000/7688) 18.1 x more time on test3
        #NUM_FILES=250          #250  files gives aprox.   (31375/499) 62.9 x more inode evictions and aprox.  (17300/1138) 15.2 x more time on test3
        #NUM_FILES=100          #100  files gives aprox.    (5050/199) 25.4 x more inode evictions and aprox.    (1600/430)  3.7 x more time on test3
        #NUM_FILES=50           #50   files gives aprox.     (1275/99) 12.8 x more inode evictions and aprox.     (560/276)  2.0 x more time on test3
        #NUM_FILES=10           #10   files gives aprox.       (55/19)  2.8 x more inode evictions and aprox.      (115/85)  1.3 x more time on test3
        #[ $populate2 = "enable" ] && populate_pre "6"  #activate populate (needs test)
        #[ $test2 = "enable" ] && test_pre "6"          #activate test (needs populate)
        ;;
    "")
        usage;;
esac
