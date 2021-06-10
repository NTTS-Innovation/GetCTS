#!/bin/bash

  disks=$(lsblk -dpno name)
  unformated_disks="/dev/nvme1n1"
  for d in $disks
    do
      if [[ $(/sbin/sfdisk -d ${d} 2>&1) == "" ]]; then
        echo "Device $d is not partitioned"
        unformated_disks="$d $unformated_disks"
      fi
  done
  echo ""
  if [[ ${unformated_disks} == "" ]]; then
    echo "No unformated disks for data storage was found. Please add a unpartitioned disk and"
    echo "  start this installer again. Aborting..."
    exit 1
  fi
  while :
    do
      read -p "Type disk path for partition: " disk
      if [[ "${disks}" != *"${disk}"* ]]; then
        echo "${disk} was not found!, please type from list above"
      else
        if [[ "${unformated_disks}" != *"${disk}"* ]]; then
          echo "${disk} is not empty. Remove all partitions and start this installer again."
          exit 1
        else
          break
        fi
      fi
  done
  while :
    do
      echo ""
      echo "This is the disk you are about to partition and all data will be deleted"
      fdisk -l $disk
      echo ""
      echo ""
      echo "Are you SURE you want to delete all data on $disk?"
      read -p "Type YES to delete all data and partition $disk: " INPUT
      if [[ "${INPUT}" == "YES" ]]; then
        break
      fi
      echo "If you want to abort and restart install please press CTRL+C"
  done

