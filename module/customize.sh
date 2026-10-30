SKIPUNZIP=0

ui_print "****************************************************"
ui_print "* Samsung Galaxy S20 Ultra BCM4375 Bluetooth Fix  *"
ui_print "* Version: 3.0                                     *"
ui_print "* Author: Amit Kumar Gandhi (iamitgandhi)          *"
ui_print "****************************************************"
ui_print "- Installing module files..."

# Set standard permissions
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/post-fs-data.sh 0 0 0755
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/libbluetooth_jni.so 1000 1000 0644 "u:object_r:system_lib_file:s0"
set_perm $MODPATH/interop_database.conf 1002 1002 0660 "u:object_r:bluetooth_data_file:s0"

ui_print "- Configured SELinux contexts and permissions."
ui_print "- Done! Please reboot your device to apply fixes."
