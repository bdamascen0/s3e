#!/bin/bash
# s3e.sh
# Simple Syscall Signature Emulator
# version 4.7
# Copyright (c) 2022 Bruno Damasceno <bdamasceno@hotmail.com.br>


#add /usr/sbin to $PATH. needed for btrfs compsize modprobe and blockdev on debian
if [[ `echo \`env | grep PATH | grep sbin | wc -l\`` = 0 ]]; then
    PATH=$PATH:/usr/sbin
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

dtest0="populate/test.          test renameat2 syscall w/ empty files (zstd) - ref implementation based on fdmanana's script"
dtest1="unlink/populate + test. test renameat2/openat syscalls w/ empty files (3x = zstd, lzo, none)"
dtest2="unlink/populate + test. test renameat2/openat + newfstatat + write syscalls (non empty files, 3x)"
dtest3="populate + test.        test renameat2/openat + unlink syscalls w/ empty files (3x)"
dtest4="populate + test.        test renameat2/openat + unlink + newfstatat + write syscalls (non empty files, 3x)"
dtest5="populate + test.        test rename   /openat + unlink + newfstatat + write syscalls (non empty files, 3x)"


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
    #dumb pause so bpftrace has time to attach its probe
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
    echo "Job took $dur ms"
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
    echo "Renames took $dur ms"
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
        #NUM_FILES=50           #50   files gives aprox.  1.6 x more time and aprox.  25 x more inode evictions for compressed files on the 5.15 kernel
        #NUM_FILES=100          #100  files gives aprox.  3.4 x more time and aprox.  50 x more inode evictions for compressed files on the 5.15 kernel
        #NUM_FILES=150          #150  files gives aprox.  6.6 x more time and aprox.  75 x more inode evictions for compressed files on the 5.15 kernel
        #NUM_FILES=200          #200  files gives aprox.  9.7 x more time and aprox. 100 x more inode evictions for compressed files on the 5.15 kernel
        #NUM_FILES=250          #250  files gives aprox. 14.3 x more time and aprox. 125 x more inode evictions for compressed files on the 5.15 kernel
        #NUM_FILES=1000         #1000 files gives aprox. 30.1 x more time and aprox. 100 x more inode evictions for compressed files on the 5.15 kernel
        #[ $populate2 = "enable" ] && populate_pre "6"  #activate populate (needs test)
        #[ $test2 = "enable" ] && test_pre "6"          #activate test (needs populate)
        ;;
    "")
        usage;;
esac
