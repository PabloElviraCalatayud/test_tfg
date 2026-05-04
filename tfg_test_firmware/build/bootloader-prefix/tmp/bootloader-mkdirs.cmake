# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION 3.5)

file(MAKE_DIRECTORY
  "/home/pelvira/esp/esp-idf/components/bootloader/subproject"
  "/home/pelvira/Documents/Universidad/tfg_test_firmware/build/bootloader"
  "/home/pelvira/Documents/Universidad/tfg_test_firmware/build/bootloader-prefix"
  "/home/pelvira/Documents/Universidad/tfg_test_firmware/build/bootloader-prefix/tmp"
  "/home/pelvira/Documents/Universidad/tfg_test_firmware/build/bootloader-prefix/src/bootloader-stamp"
  "/home/pelvira/Documents/Universidad/tfg_test_firmware/build/bootloader-prefix/src"
  "/home/pelvira/Documents/Universidad/tfg_test_firmware/build/bootloader-prefix/src/bootloader-stamp"
)

set(configSubDirs )
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "/home/pelvira/Documents/Universidad/tfg_test_firmware/build/bootloader-prefix/src/bootloader-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "/home/pelvira/Documents/Universidad/tfg_test_firmware/build/bootloader-prefix/src/bootloader-stamp${cfgdir}") # cfgdir has leading slash
endif()
