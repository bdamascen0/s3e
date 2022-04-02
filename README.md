# Simple Syscall Signature Emulator  
&copy; 2022 Bruno Damasceno bdamasceno@hotmail.com.br  
  
## Description:  
This program is a simple system call signature emulator script for the linux kernel integrated with:  
* populate, test and measurement functions for the btrfs filesystem.  
* several test functions with different syscall signatures.  
* several measurement functions to provide duration, cpu and inode-eviction analysis.  
* ramdisk setup, formatting, mounting and reseting.  
* folder layout setup.  
* safety checks.  
  
## About this work  
This work is about a severely degraded performance found during rpm operations with specific packages on openSUSE Tumbleweed.

More specifically, the issue happens with the 5.15 LTS kernel on a btrfs partition with btrfs compression property enabled at the target folder.

A bug [1] was filled on openSUSE but the root cause wasn't found and it was considered a kernel regression outside the btrfs code.  

The bug was later cross-referenced on a kernel patchset for btrfs [2] where Filipe Manana gave it the following description:
"The issue was caused indirectly due to an excessive number of inode evictions on a 5.15 kernel, about 100x more compared to a 5.13, 5.14 or a 5.16-rc8 kernel."  

The patchset also provided a script that mimics a portion of the rpm operations to test the btrfs improvements and it got me thinking if the regression could be triggered without rpm itself.
I saw it as a great opportunity since my original reproduction instructions [3] were absolutely tied to the opensuse environment.  

It didn't work at first so I decided to use the strace results as a starting point with the objective to add the missing system calls to the script.

After some ramdisk block device learning and some bash workout I got an easy testing setup for this syscall signature research.
Add more kvm, bash and distro hours and I could also test newer 5.15 kernels from Zenwalk, Debian and Ubunt to make sure the situation hasn't changed.

The main motivation for this development was to improve the regression reproduction and, as a bonus, I was rewarded by discovering the possible guilty syscall combination.
I hope both achievements to be enough incentive to get it further investigated by kernel developers.  

[1] https://bugzilla.opensuse.org/show_bug.cgi?id=1193549  
[2] https://lore.kernel.org/linux-btrfs/285785ef66283fb6b00fe69112dc1240a2aa1e19.1642676248.git.fdmanana@suse.com/  
[3] https://lore.kernel.org/linux-fsdevel/MN2PR20MB251235DDB741CD46A9DD5FAAD24E9@MN2PR20MB2512.namprd20.prod.outlook.com/T/  
  
## The original system call signature  
This program tries to replicate part of the syscall sequecence observed on some rpm operations that triggered the regression.  
Follow the original syscall signature sample captured with strace (single file excerpt):  
```
newfstatat(AT_FDCWD, "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz", {st_mode=S_IFREG|0644, st_size=7362, ...}, AT_SYMLINK_NOFOLLOW) = 0  
newfstatat(AT_FDCWD, "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE", 0x7ffd3a183a20, AT_SYMLINK_NOFOLLOW) = -1 ENOENT (No such file or directory)  
rename("/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz", "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE") = 0  
newfstatat(AT_FDCWD, "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE", {st_mode=S_IFREG|0644, st_size=7362, ...}, AT_SYMLINK_NOFOLLOW) = 0  
unlink("/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE") = 0  
umask(0577)                             = 022  
openat(AT_FDCWD, "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz", O_WRONLY|O_CREAT|O_EXCL|O_TRUNC, 0666) = 13  
fcntl(13, F_SETFD, FD_CLOEXEC)          = 0  
umask(022)                              = 0577  
write(13, "\37\213\10\0\0\0\0\0\0\3\265]ms\3338\222\376\274\371\25(WmU&76ER\324K"..., 7362) = 7362  
write(3, "'\0\0\0", 4)                  = 4  
write(3, "\n!zypp.proto.target.PackageProgr"..., 39) = 39  
close(13)  
```
## The "inode-eviction" system call signature -  
After testing several different combinations, the minimum theorical syscall signature to trigger the regression would be:  
```
rename("/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz", "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE") = 0  
unlink("/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz-RPMDELETE") = 0  
openat(AT_FDCWD, "/usr/share/cups/model/gutenprint/5.2/C/stp-panasonic-dp-c265.5.2.ppd.gz", O_WRONLY|O_CREAT|O_EXCL|O_TRUNC, 0666) = 13  
```
This way, we should rename a file, unlink the renamed file and create a new file.  
The file existence check and the file content writing didn't demonstrated any first order impact.  
For simplification, the fcntl and close syscalls were considered consequences of openat for empty and non empty files.  
The umask changes weren't tested.  

Please note that this program can not provide a clean syscall sequence as the shell interpreter and the external programs executed by the script will generate their own system calls too.

Another remark goes to the rename operation.
While the rename program from util-linux generates a rename syscall, the mv program from coreutils generates a renameat2 syscall.
Both were verified to trigger the regression and the major factor here is that the util-linux rename isn't easily availble on some distributions like Ubuntu.  
  
## Triggering the regression  
The bare minimum elements to trigger the regression are:  
* the 5.15 kernel series (since 5.15.0-rc1).  
* a btrfs partition.  
* the minimun syscall signature targeting files with btrfs compression property.  

Verify the dependencies and run the s3e.sh program on any 5.15 kernel.  

* Tests 1 and 2  
These tests do not produce the minimum syscall signature.  
They should be fast on all folders (uncompressed, zstd and lzo folders).  
* Tests 3, 4 and 5  
These tests do produce the minimum syscall signature.  
They should be fast on the uncompressed folder.  
They should be a lot slower on the zstd and lzo folders.  

Test 3 is considered the most significant as it produces the minimum syscall signature and uses the widely available mv program.  

The slow results on tests 3, 4 and 5 are due:  
a) the kernel regression: specific system calls touching files with btrfs compression property will generate higher inode eviction on 5.15 kernels.  
b) the inode eviction generating btrfs inode logging and directory logging.  
c) the btrfs directory logging on the 5.15 kernel not being particulary efficient in the presence of high inode eviction.  

About "a": AFAIK there isn't any work for "a" yet and the regression remains unfixed.  

About "c": There is already an ongoing work [1] to improve "c" on newer kernels but I was told they are not elegible for the 5.15 version due to backporting restrictions.  

The consequence is that btrfs users running the 5.15 kernel may experience severely degraded performance for specific I/O workloads on files with the compression property enabled.  

[1] https://bugzilla.opensuse.org/show_bug.cgi?id=1193549  
  
## Main results  

The regression could be reproduced reliably on:  
* several different 5.15 kernels versions across several different distros.  
* all 5.15 kernels that I have tried on.  
* the 5.15.0-rc1 kernel from the opensuse tumbleweed comunity repository.  
* the 5.15.12 vanilla kernel from the official opensuse tumbleweed repository [1].  
* the 5.15.32 vanilla kernel from the official ubuntu repository [2].  

The regression could not be reproduced on:  
* kernel versions other than the 5.15.  
* the 5.17.1 and 5.16.15 vanilla kernels from the official opensuse tumbleweed repository [1].  

The vanilla kernel tests were suggested by Thorsten Leemhuis [3] to make sure downstream custom patches aren't causing the symptoms.  
The vanilla kernel tests result show the exact same pattern verified on downstream kernels and fully validates the regression.  

[1] https://software.opensuse.org/package/kernel-vanilla?search_term=kernel-vanilla  
[2] https://wiki.ubuntu.com/Kernel/MainlineBuilds   
[3] https://lore.kernel.org/linux-fsdevel/07bb78be-1d58-7d88-288b-6516790f3b5d@leemhuis.info/  
  
### General test results for the 5.15 kernel series (x86_64)  
```
__T E S T - 3 - populate + test. test renameat2/openat + unlink syscalls w/ empty files (3x)  
opensuse tumbleweed ----- kernel 5.15.0-rc1-1.g8787773 - (kvm)  
...updating 250 files on /mnt/inode-ev/zstd:         Job took 13875 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/lzo:          Job took 15351 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  1231 ms @inode_evictions: 499  
opensuse tumbleweed ----- kernel 5.15.12 --- vanilla --- (kvm)  
...updating 250 files on /mnt/inode-ev/zstd:         Job took 13327 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/lzo:          Job took 13361 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  1204 ms @inode_evictions: 499  
opensuse tumbleweed ----- kernel 5.15.12----------------------  
...updating 250 files on /mnt/inode-ev/zstd:         Job took 12500 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/lzo:          Job took 12327 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  1482 ms @inode_evictions: 499  
debian bookworm --------- kernel 5.15.0-3 - (5.15.15) -- (kvm)  
...updating 250 files on /mnt/inode-ev/zstd:         Job took 12343 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/lzo:          Job took 14028 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  1092 ms @inode_evictions: 499  
Zenwalk 15.0 Skywalker ---kernel 5.15.19 --------------- (kvm)  
...updating 250 files on /mnt/inode-ev/zstd:         Job took 14374 ms @inode_evictions: -  
...updating 250 files on /mnt/inode-ev/lzo:          Job took 14163 ms @inode_evictions: -  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  2173 ms @inode_evictions: -  
ubuntu jammy jellyfish -- kernel 5.15.0.23 - (5.15.27) - (kvm)   
...updating 250 files on /mnt/inode-ev/zstd:         Job took 17521 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/lzo:          Job took 17114 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  1138 ms @inode_evictions: 499  
ubuntu jammy jellyfish -- kernel 5.15.32 --- vanilla --- (kvm)   
...updating 250 files on /mnt/inode-ev/zstd:         Job took 16191 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/lzo:          Job took 16062 ms @inode_evictions: 31375  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  1149 ms @inode_evictions: 499  
```
### General test results for other kernels (x86_64)  
```
__T E S T - 3 - populate + test. test renameat2/openat + unlink syscalls w/ empty files (3x)  
opensuse leap 15.3 ------ kernel 5.3.18-150300.59.54----------  
...updating 250 files on /mnt/inode-ev/zstd:         Job took  668 ms @inode_evictions: 251  
...updating 250 files on /mnt/inode-ev/lzo:          Job took  693 ms @inode_evictions: 251  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  661 ms @inode_evictions: 252  
opensuse leap 15.4 beta - kernel 5.14.21-150400.11 ----- (kvm)  
...updating 250 files on /mnt/inode-ev/zstd:         Job took  811 ms @inode_evictions: 251  
...updating 250 files on /mnt/inode-ev/lzo:          Job took  912 ms @inode_evictions: 251  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  993 ms @inode_evictions: 251  
opensuse tumbleweed ----- kernel 5.14.14 --------------- (kvm)  
...updating 250 files on /mnt/inode-ev/zstd:         Job took  888 ms @inode_evictions: 251  
...updating 250 files on /mnt/inode-ev/lzo:          Job took 1063 ms @inode_evictions: 251  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  778 ms @inode_evictions: 251  
opensuse tumbleweed ----- kernel 5.16.14----------------------  
...updating 250 files on /mnt/inode-ev/zstd:         Job took 1398 ms @inode_evictions: 250  
...updating 250 files on /mnt/inode-ev/lzo:          Job took 1323 ms @inode_evictions: 250  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took 1365 ms @inode_evictions: 250  
opensuse tumbleweed ----- kernel 5.16.15 --- vanilla --- (kvm)  
...updating 250 files on /mnt/inode-ev/zstd:         Job took  910 ms @inode_evictions: 250  
...updating 250 files on /mnt/inode-ev/lzo:          Job took  740 ms @inode_evictions: 250  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  717 ms @inode_evictions: 250  
opensuse tumbleweed ----- kernel 5.17.1 ---- vanilla --- (kvm)  
...updating 250 files on /mnt/inode-ev/zstd:         Job took  701 ms @inode_evictions: 250  
...updating 250 files on /mnt/inode-ev/lzo:          Job took  695 ms @inode_evictions: 250  
...updating 250 files on /mnt/inode-ev/uncompressed: Job took  954 ms @inode_evictions: 250  
```  
### Load test results (x86_64):  
opensuse leap 15.4 beta has an up-to-date downstream 5.14 kernel.  
ubuntu jammy jellyfish  has up-to-date downstream and vanilla 5.15 kernels.  
```
__T E S T - 3 - populate + test. test renameat2/openat + unlink syscalls w/ empty files (3x)  
opensuse leap 15.4 beta - kernel 5.14.21-150400.11 ----- (kvm)  
...updating   50 files on /mnt/inode-ev/zstd:         Job took    261 ms @inode_evictions: 51  
...updating   50 files on /mnt/inode-ev/lzo:          Job took    256 ms @inode_evictions: 51  
...updating   50 files on /mnt/inode-ev/uncompressed: Job took    317 ms @inode_evictions: 51  
...updating  100 files on /mnt/inode-ev/zstd:         Job took    450 ms @inode_evictions: 101  
...updating  100 files on /mnt/inode-ev/lzo:          Job took    461 ms @inode_evictions: 101  
...updating  100 files on /mnt/inode-ev/uncompressed: Job took    471 ms @inode_evictions: 101  
...updating  150 files on /mnt/inode-ev/zstd:         Job took    618 ms @inode_evictions: 151  
...updating  150 files on /mnt/inode-ev/lzo:          Job took    624 ms @inode_evictions: 151  
...updating  150 files on /mnt/inode-ev/uncompressed: Job took    612 ms @inode_evictions: 151  
...updating  200 files on /mnt/inode-ev/zstd:         Job took    822 ms @inode_evictions: 201  
...updating  200 files on /mnt/inode-ev/lzo:          Job took    933 ms @inode_evictions: 201  
...updating  200 files on /mnt/inode-ev/uncompressed: Job took    747 ms @inode_evictions: 201  
...updating  250 files on /mnt/inode-ev/zstd:         Job took   1128 ms @inode_evictions: 251  
...updating  250 files on /mnt/inode-ev/lzo:          Job took    974 ms @inode_evictions: 251  
...updating  250 files on /mnt/inode-ev/uncompressed: Job took    936 ms @inode_evictions: 251  
...updating 1000 files on /mnt/inode-ev/zstd:         Job took   3517 ms @inode_evictions: 1001  
...updating 1000 files on /mnt/inode-ev/lzo:          Job took   4373 ms @inode_evictions: 1001  
...updating 1000 files on /mnt/inode-ev/uncompressed: Job took   3797 ms @inode_evictions: 1001  
ubuntu jammy jellyfish -- kernel 5.15.32 --- vanilla --- (kvm)   
...updating   50 files on /mnt/inode-ev/zstd:         Job took    420 ms @inode_evictions: 1275  
...updating   50 files on /mnt/inode-ev/lzo:          Job took    488 ms @inode_evictions: 1275  
...updating   50 files on /mnt/inode-ev/uncompressed: Job took    269 ms @inode_evictions: 99  
...updating  100 files on /mnt/inode-ev/zstd:         Job took   1649 ms @inode_evictions: 5050  
...updating  100 files on /mnt/inode-ev/lzo:          Job took   1566 ms @inode_evictions: 5050  
...updating  100 files on /mnt/inode-ev/uncompressed: Job took    359 ms @inode_evictions: 199  
...updating  150 files on /mnt/inode-ev/zstd:         Job took   4448 ms @inode_evictions: 11325  
...updating  150 files on /mnt/inode-ev/lzo:          Job took   4136 ms @inode_evictions: 11325  
...updating  150 files on /mnt/inode-ev/uncompressed: Job took    675 ms @inode_evictions: 299  
...updating  200 files on /mnt/inode-ev/zstd:         Job took   9177 ms @inode_evictions: 20100  
...updating  200 files on /mnt/inode-ev/lzo:          Job took   9070 ms @inode_evictions: 20100  
...updating  200 files on /mnt/inode-ev/uncompressed: Job took    752 ms @inode_evictions: 399  
...updating  250 files on /mnt/inode-ev/zstd:         Job took  16191 ms @inode_evictions: 31375  
...updating  250 files on /mnt/inode-ev/lzo:          Job took  16062 ms @inode_evictions: 31375  
...updating  250 files on /mnt/inode-ev/uncompressed: Job took   1149 ms @inode_evictions: 499  
...updating 1000 files on /mnt/inode-ev/zstd:         Job took 132865 ms @inode_evictions: 104195  
...updating 1000 files on /mnt/inode-ev/lzo:          Job took 131979 ms @inode_evictions: 106639  
...updating 1000 files on /mnt/inode-ev/uncompressed: Job took   7333 ms @inode_evictions: 1999  
```  
### Load test results comparisson for compressed files (x86_64):  
ubuntu jammy jellyfish vanilla - compared to - opensuse leap 15.4 beta  
```
50   files gives aprox.  1.6 x more time and aprox.  25 x more inode evictions   
100  files gives aprox.  3.4 x more time and aprox.  50 x more inode evictions   
150  files gives aprox.  6.6 x more time and aprox.  75 x more inode evictions   
200  files gives aprox.  9.7 x more time and aprox. 100 x more inode evictions   
250  files gives aprox. 14.3 x more time and aprox. 125 x more inode evictions   
1000 files gives aprox. 30.1 x more time and aprox. 100 x more inode evictions   
```  
### Load test results comparisson for uncompressed files (x86_64):  
ubuntu jammy jellyfish vanilla - compared to - opensuse leap 15.4 beta  
```
50   files gives aprox. 0.8 x more time and aprox. 2 x more inode evictions   
100  files gives aprox. 0.7 x more time and aprox. 2 x more inode evictions   
150  files gives aprox. 1.1 x more time and aprox. 2 x more inode evictions   
200  files gives aprox. 1.0 x more time and aprox. 2 x more inode evictions   
250  files gives aprox. 1.2 x more time and aprox. 2 x more inode evictions   
1000 files gives aprox. 1.9 x more time and aprox. 2 x more inode evictions   
```  
### CPU usage results:  
The regression causes significant CPU usage by the kernel.  
```
__T E S T - 3 - populate + test. test renameat2/openat + unlink syscalls w/ empty files (3x)  
ubuntu jammy jellyfish -- kernel 5.15.32 --- vanilla --- (kvm)   
...updating 1000 files on /mnt/inode-ev/zstd:         Job took 132691 ms  
   real   2m12,731s  
   user   0m 1,550s  
   sys    2m 7,134s  
...updating 1000 files on /mnt/inode-ev/lzo:          Job took 134130 ms  
   real   2m14,149s  
   user   0m 1,595s  
   sys    2m 8,447s  
...updating 1000 files on /mnt/inode-ev/uncompressed: Job took   7241 ms  
   real   0m 7,256s  
   user   0m 1,325s  
   sys    0m 4,732s  
```  
## Test system specification:  
host: AMD FX-8370E 8 cores / 8GB RAM / ssd  
guests (kvm): 2 cores / 2G RAM / ssd  
test storage medium: RAM disk block device (host and guest)  
  
## Dependencies  
- Dependencies:  
modprobe, blockdev, mv, btrfs, xfs_io, compsize, grep, wc, which, kernel modules: brd*, btrfs.  
- Optional dependencies:  
rename, bpftrace, time.  
- Package names:  
kmod (modprobe), util-linux (blockdev, rename), coreutils (mv, wc), xfsprogs (xfs_io), btrfsprogs, compsize, which, bpftrace, time.  
- Specific ubuntu package names:  
btrfs-progs, btrfs-compsize, debianutils (which).  

(*) kernels compiled with ramdisk option (like zenwalk) will need additional customization.  
  
## Changes  

* 20220402  
  added results for:  
  -opensuse tumbleweed: k5.16.15 vanilla / k5.17.1 vanilla.  
* 20220330  
  added results for:  
  -ubuntu jammy jellyfish: k5.15.32 vanilla.  
* 20220327  
  overhauled test results presenting them in a more modular and meaningfull way.  
  added main results description session.  
  added load results for:  
  -opensuse leap 15.4: k5.14.  
  -ubuntu jammy jellyfish: k5.15.27.  
  added new load results comparisson session.  
* 20220326  
  added test results for:  
  -opensuse tumbleweed: k5.14.14 / k5.15.0-rc1 / k5.15.12 vanilla.  
* 20220324  
  added brief description to some test results.  
  added test results for:  
  -debian bookworm: k5.15.15.  
  -zenwalk skywalker: k5.15.19.  
* 20220320  
  revised introduction text.  
  added system resource usage results.  
* 20220319  
  added test results for:  
  -opensuse leap 15.3: k5.3.  
  -opensuse leap 15.4: k5.14.  
  -opensuse tumbleweed: k5.15.12 / k5.16.14.  
  -ubuntu jammy jellyfish: k5.15.27.  
* 20220317  
  added introduction text.   

