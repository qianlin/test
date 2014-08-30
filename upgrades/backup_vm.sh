#!/bin/bash
# Author: kui.shi@huawei.com  2014/8/12
# backup the vm image to local
# 1. create snapshot for vm "nova image-create"
# 2. download the snapshot image from glance, "glance image-download"
# 3. remove the snapshot image from glance, "glance iamge-delete"


#set -x
# check the arguments
if [ $# != 4 ]; then
    echo "Usage: $0 <rc_file> <save_img_dir>  \"<vm_id> <vm_id>\" <timeout(minute)>"
    echo "Usage: $0 <rc_file> <save_img_dir>  all <timeout(minute)>"
    exit 0
fi

BEGIN_TIME=$(date +%s)

rc_file=`readlink -f $1`
backup_dir="$2"
vm_id_list="$3"
timeout=$4


mkdir -p $backup_dir

# check the return value
err_trap()
{
    echo "[LINE:$1] command or function exited with status $?"
}
#trap 'err_trap $LINENO' ERR

# source the OS variables
source $rc_file

# check the connection to OpenStack
nova list >/dev/null 2>&1


# create file to save vm info in $backup_dir
current_time=`date +%Y%m%d%H%M%S`
vm_info_file=$backup_dir/vm_info_$current_time
log_file=$backup_dir/log_$current_time
failed_file=$backup_dir/failed_$current_time
touch $vm_info_file
touch $log_file
touch $failed_file

# loop all the vm, and download them
if [ "all" = "$vm_id_list" ]; then
    echo "all vm will be saved\n" 
    declare -a vm_id_list=(`nova list --minimal  --all-tenants |grep "|" |grep -v "ID *| Name" | awk -F '|' '{print $2}'`)
    echo ${vm_id_list[@]}
fi

for i in ${vm_id_list[@]};
do
    snapshot_name=${i}-snapshot

    # get vm info (id / name )
    start_time=$(date +%s)
    vm_name=`nova show $i |grep '| name' | awk -F'|' '{print $3}'`
    vm_name=`echo $vm_name |sed 's/ //g'`
    id=$i

    echo "Saving VM: $i ${vm_name}" | tee -a $log_file
    image_file=${backup_dir}/${snapshot_name}-${vm_name}

    # create snapshot for vm
    echo "nova image-create ${i} ${snapshot_name}"  | tee -a $log_file
    retries=1
    failed_vm=""
    while [ $retries -lt 4 ]; do
	echo "create image $retries "  | tee -a $log_file
        create_message=`nova image-create ${i} ${snapshot_name} 2>&1`
        if [ "$create_message" != "" ]; then
	    echo "retry to create snapshot"  | tee -a $log_file
            nova reset-state --active ${i}
	else
            echo "snapshot is created"  | tee -a $log_file
	    break
        fi
	retries=$(($retries + 1))
        if [ $retries -eq 4 ]; then
	    failed_vm="yes"
        fi
    done

    if [ "$failed_vm" != "" ]; then
	echo -e "\n**** Failed to create snapshot for $i $vm_name ****"  | tee -a $log_file
	echo -e "**** continue to process next vm \n"   | tee -a $log_file
	echo $i $vm_name >> $failed_file
	continue
    fi
 
    # confirm the snapshot image
    echo "glance image-list --name ${snapshot_name}"  | tee -a $log_file
    retries=$timeout
    failed_vm=""
    while [ $retries -gt 0 ]; do
	glance image-list --name ${snapshot_name} --status ACTIVE | grep ${snapshot_name} >/dev/null 2>&1
	[ 0 = $? ] && break
	sleep 60
        if [ $retries -eq 1 ]; then
	    failed_vm="yes"
        fi
	retries=$(($retries - 1))
    done

    if [ "$failed_vm" != "" ]; then
	echo -e "\n**** Failed to upload snapshot image for $i $vm_name "  | tee -a $log_file
	echo -e "**** continue to process next vm \n"  | tee -a $log_file
	echo $i $vm_name >> $failed_file
	continue
    fi

    # download the snapshot image
    echo "glance image-download --file ${image_file} ${i}-snapshot"  | tee -a $log_file
    glance image-download --file ${image_file} ${snapshot_name}

    echo "glance image-delete ${snapshot_name}"  | tee -a $log_file
    glance image-delete ${snapshot_name}

    # stastistics
    end_time=$(date +%s)
    interval=$(($end_time - $start_time))
    ELAPSE_TIME=$((end_time - $BEGIN_TIME))

    image_size=`ls ${image_file} -lh | awk '{print $5}'`
    # save the vm info
    echo $id $vm_name >> $vm_info_file
    echo -e "\n#########################"  | tee -a $log_file
    echo -e "VM saved: ${image_file}  Size: $image_size  Used time: $interval  Elapse time: $ELAPSE_TIME"  | tee -a $log_file
    echo -e "#########################\n"   | tee -a $log_file
done


# print statistics
echo "VM downloaded: "  $(wc -l ${vm_info_file} | awk '{print $1}')  | tee -a $log_file
echo "VM failed: " $(wc -l ${failed_file} | awk '{print $1}')  | tee -a $log_file

