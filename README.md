ODROID Debian build script
==========================
Author: Tomasz Gwozdz [Jarlath] http://www.jarlath.net

 This script is provided as-is, no warranty is provided or implied.
 The author is NOT responsible for any damages or data loss that may occur
 through the use of this script.  Always test, test, test before
 rolling anything into a production environment.

 This script is free to use for both personal and business use, however,
 it may not be sold or included as part of a package that is for sale.

 A Service Provider may include this script as part of their service
 offering/best practices provided they only charge for their time
 to implement and support.

 For distribution and updates go to: http://www.jarlath.net :
 http://www.jarlath.net/2014/11/skrypt-do-budowy-debiana-dla-odroid-u3/
Description
-----------
Script create microSD debian bootable card for ODROID development board.
Tested on Debian x86 VM  with microSD card or eMMC with microSD adapter


Supported devices:
* ODROID-U2 [Not tested, but should work]
* ODROID-U3 [OK]



Based on:<br>
http://forum.odroid.com/viewtopic.php?f=79&t=5513<br>
https://doukki.net/doku.php?id=hard:arm:odroid:odroid-u3-debian

History
-------
20141206
* Some improvements. Not tested, but no changes in main routine are made. For tested working version goto v0.1<br>
TODO
* Less info visible on console
* More echos
* passwd procedure (loop if user make mistake)

v0.1:
* Added UUID for second partition

20141124: initial version
* Build script working fine for U3
