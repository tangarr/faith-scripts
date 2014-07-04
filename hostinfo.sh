#!/bin/bash

#-------ZMIENNE------------
db_name="host.db"
db_open_cmd="sqlite3 $db_name"


#-------FUNKCJE------------
bytes_to_megabytes()
{
	div=`expr $1 / 1048576`
	mod=`expr $1 % 1048576`

	if [ $mod -ge 524288 ]
	then
		expr $div + 1
	else
		echo $div
	fi
}
get_interfaces()
{
	ifconfig -a | awk '/^[a-z]+/ && !/^lo /{print $1}'
}
get_if_ip()
{
	if [ -z $1 ]  
	then
		echo error: błędny parametr funkcji get_if_ip 
		exit 1 
	fi
	ifconfig $1 | awk -F"[: ]" '/inet addr/{print $13}'
}
get_if_hw()
{
	if [ -z $1 ]  
	then
		echo error: błędny parametr funkcji get_if_hw 
		exit 1 
	fi
	ifconfig eth0 | awk '/HWaddr/{print $5}'
}
db_execute()
{
	echo "SQL: " $1
	echo $1 | $db_open_cmd
}
db_create_tab_general()
{
    db_execute "create table general (key text primary key, value text);"
}
db_create_tab_disk()
{
	db_execute "create table disk (dev text, size text, pt_type text);" 
	db_execute "create table partition (dev text, id int, size text, fs_type text, flags text, primary key (dev, id), foreign key(dev) references disk(dev) );" 
}
db_insert_primary_mac()
{
    IP_ADDR=$(host $SERVER | awk '/has address/ { print $4 }') 
    if [ -z $IP_ADDR ]
    then
        IP_ADDR="8.8.8.8"
    fi   
    ip route get $IP_ADDR | awk '/dev/{ print $5 }'
    iface=$(ip route get $IP_ADDR | awk '/dev/{ print $5 }')
    hw=$(get_if_hw $iface)
    db_execute "insert into general values ('mac','$hw');"
}
get_disks()
{
	LC_ALL=C fdisk -l | awk -F"[ :/]" '/Disk \//{print $4}'	
}

get_disk_size()
{
	bytes=$(LC_ALL=C fdisk -l 2>/dev/null | awk -F"[ ,]" '/Disk \/dev\/'$1'/ {print $6}')
	mib=$(bytes_to_megabytes $bytes)
	echo $mibMiB	
}
get_disk_label()
{
	LC_ALL=C parted /dev/$1 unit MiB print | awk '/Partition Table:/{print $3}'
}
get_partitions()
{
	LC_ALL=C parted /dev/$1 unit MiB print | grep '^ [1-9][0-9]*' | awk '{print $1 "_" $4 "_" $5 "_" $6 "_" $7}'
}
db_insert_disks()
{
	for disk_dev in $(get_disks)
	do
		disk_size=$(get_disk_size $disk_dev)
		disk_label=$(get_disk_label $disk_dev)
		db_execute "insert into disk values ('$disk_dev','$disk_size','$disk_label');"
		for part_line in $(get_partitions $disk_dev)
		do
			part_id=$(echo $part_line | awk -F_ '{print $1}')
			part_size=$(echo $part_line | awk -F_ '{print $2}')
			part_type=$(echo $part_line | awk -F_ '{print $3}')
			part_fstype=$(echo $part_line | awk -F_ '{print $4}')
			part_flags=$(echo $part_line | awk -F_ '{print $5}')			
			if [ $part_type == "extended" ] 
			then				
				if [ -z $part_flags ]
				then
					part_flags=extended
				else
					part_flags=$part_flags,extended
				fi
			fi	
			case "$part_fstype" in
				*swap* ) part_fstype="swap";;
			esac		
			db_execute "insert into partition values ('$disk_dev', $part_id,'$part_size', '$part_fstype', '$part_flags');"			
		done
	done
}
init()
{
	if [[ $UID -ne 0 ]]
	then
		echo "$0 must be run as root"
		exit 1
	fi

	if [ -z $SERVER ]
	then
		echo 'Variable $SERVER not set'
		exit 1		
	fi

	if [ -e $db_name ]
	then
		rm $db_name
	fi 
}

#--------MAIN--------------

init
db_create_tab_general
db_create_tab_disk
db_insert_primary_mac
db_insert_disks

exit 0
