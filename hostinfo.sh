#!/bin/bash

#-------ZMIENNE------------
db_name="host.db"
db_open_cmd="sqlite3 $db_name"


#-------FUNKCJE------------
bytes_to_megabytes()
{
	div=`expr $1 / 1000000`
	mod=`expr $1 % 1000000`

	if [ $mod -ge 500000 ]
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
#db_create_tab_ifaces()
#{
#	db_execute "create table ifaces (dev text, hwaddr text, ip text);"
#}
db_create_tab_general()
{
    db_execute "create table general (key text primary key, value text);"
}
db_create_tab_disk()
{
	db_execute "create table disk (dev text, size text, pt_type text);" 
	db_execute "create table partition (dev text, id int, size text, fs_type text, flags text, primary key (dev, id), foreign key(dev) references disk(dev) );" 
}
#db_insert_ifaces()
#{
#	for dev in $(get_interfaces)
#	do
#		ip=$(get_if_ip $dev)
#		hw=$(get_if_hw $dev)
#		db_execute "insert into ifaces values ('$dev','$hw','$ip');"
#	done
#}
db_insert_primary_mac()
{
    iface=$(ip route get $SERVER | awk '/dev/{ print $5 }')
    hw=$(get_if_hw $iface)
    db_execute "insert into general values ('mac','$hw');"
}
get_disks()
{
	LC_ALL=C fdisk -l | awk -F"[ :/]" '/Disk \//{print $4}'	
}

get_disk_size()
{
	LC_ALL=C fdisk -l 2>/dev/null | awk -F"[ ,]" '/Disk \/dev\/'$1'/ {print $3$4}'
}

db_insert_disks()
{
	#for line in $(LC_ALL=C parted -lm | tr -d '\r' | sed -e 's/^[ \t]*//')
	for line in $(LC_ALL=C parted -lm | tr -d '\r' | awk '{$1 = $1; print }' | sed 's/ /_SPACE_/g')
	do
		line=$(echo $line | sed 's/_SPACE_/ /g')
		#echo LINE=$line
		case $line in
		BYT";"	) unit=BYT ;;
		CHS";"	) unit=CHS ;;
		CYL";"	) unit=CYL ;;
		/dev/*";" 	)
			disk_dev=$(echo $line | awk -F"[:/]" '{ print $3 }' )
			disk_size=$(echo $line | awk -F: '{print $2}')
			disk_pt_type=$(echo $line | awk -F: '{print $6}')
			#echo $disk_dev:$disk_size:$disk_pt_type
			db_execute "insert into disk values ('$disk_dev','$disk_size','$disk_pt_type');"
					
		;;
		[[:digit:]+]:*	)
			part_id=$(echo $line | awk -F"[:]" '{ print $1 }' )
			part_size=$(echo $line | awk -F"[:]" '{ print $4 }' )
			part_fstype=$(echo $line | awk -F"[:]" '{ print $5 }' )
			part_flags=$(echo $line | awk -F"[:;]" '{ print $7 }' )
			if [ $disk_pt_type = msdos ] && [ -z $part_fstype  ] 
			then
				if [ -z $part_flags ]
				then
					part_flags=extended
				else
					part_flags=$part_flags,EXTENDED
				fi
			fi
			#echo $part_id:$part_size:$part_fstype:$part_flags
			db_execute "insert into partition values ('$disk_dev', $part_id,'$part_size', '$part_fstype', '$part_flags');"			
			;;
		"Error: /dev/"*": unrecognised disk label")
			unit=""
			disk_dev=$(echo $line | awk -F"[:/]" '{ print $4}' )
			disk_pt_type=""
			disk_size=$(get_disk_size $disk_dev)
			echo $disk_dev:$disk_size:$disk_pt_type
			;;
		* ) echo $unit " # " $line ;;
		esac
			
		#case $line in
		#	*";"	 ) echo jest srednik ;;
		#	#[0-9]* ) echo liczba ;;
		#	*	 ) echo nie ma srednika ;;
		#esac
	done
	#for d in $(get_disks)
	#do
	#	get_disk_size $d
	#done
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
