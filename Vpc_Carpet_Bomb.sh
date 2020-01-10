#!/bin/bash
##################################################################

## This script will destroy your account if you are not careful ##
## This script could irreversably cripple your infastructure if you are not careful ##
RED='\033[0;31m'
NC='\033[0m'
echo "Ji"
## Warning Banner and acknowledgement section ##
while (true); do
    clear
    echo -e """ ${RED}
    
    #     #    #    ######  #     # ### #     #  #####  
    #  #  #   # #   #     # ##    #  #  ##    # #     # 
    #  #  #  #   #  #     # # #   #  #  # #   # #       
    #  #  # #     # ######  #  #  #  #  #  #  # #  #### 
    #  #  # ####### #   #   #   # #  #  #   # # #     # 
    #  #  # #     # #    #  #    ##  #  #    ## #     # 
     ## ##  #     # #     # #     # ### #     #  ##### 
     
     """
    echo -en """${NC}This script is dangerous! It will ruin your account in irreversible ways if you are not careful!
This script will attempt to delete a single specified VPC from a region, or wipeout all VPCs in a region.
If you run this script carelessly, or without permission you could irreverably damage or even destory your company.
Please be careful when using this. 
Are you certain you wish to proceed?

To proceed type 'This may ruin my account, and I accept that.' 
Statement: """
    read response
    if [[ "${response}" == "This may ruin my account, and I accept that." ]]; then
        break
    fi
done
clear
tput clear
##################################################################


## Gets region and validates answer ##
while (true); do
    echo -n "Enter the region you wish you destroy: "
    read REGION
    if echo `aws ec2 describe-regions | grep RegionName | cut -d '"' -f 4` | grep -w ${REGION}  > /dev/null 2>&1; then
        break
    else
        clear
        echo "Not a valid region! Try again."
    fi
done
clear
##################################################################

# Use describes to delete all EC2 instances, subnets,  
#Useful https://aws.amazon.com/premiumsupport/knowledge-center/troubleshoot-dependency-error-delete-vpc/

## Gets list of all VPCs in a region. Asks user which VPC they want to destory, or if they want to wipe them all.

## Make this optional later for bigger accounts. 
echo "Would you like generate a list of all VPCs in ${REGION}? y/n"
echo -n "Answer: "
read response
case "$response" in
    [yY][eE][sS]|[yY]) 
        Aws_Query=`aws ec2 --region ${REGION} describe-vpcs`
        Vpc_Count=`echo $Aws_Query | jq '.Vpcs[]' | jq length | wc -l`
        echo "Generating a list of all VPCs found in the region. This make take a while depending on how many are in the account. "
        for i in $(seq 1 "$Vpc_Count" ); do
            Vpc_Id_Temp=`echo $Aws_Query | jq ".Vpcs[$(( $i - 1 )) ] .VpcId"` ### TODO make it so the list starts at 1 and substract 1 from i here instead ###
            echo ${i}". "${Vpc_Id_Temp}
            declare vpc_${i}=${Vpc_Id_Temp}
            Option_list=`echo "$Option_list\n${i}. ${Vpc_Id_Temp}"`
        done
esac
##################################################################

## Choose method of deleting VPCs ##
echo -n """
Use one of the following methods to specify which VPCs you would like to delete.
1. Enter a list of comma sperated VPC IDs that you want to delete (e.g vpc-xxxxxxxxx,vpc-yyyyyyyyy,vpc-zzzzzzzzzz).
2. Enter the path to a file that contains the VPC IDs. Have one ID per line in this file.
3. Enter "All" as a value and all VPCs will be deleted.

Input: """
read input
##################################################################

## Function Section ##
function Delete_All () {
    echo "Delete_All"
    #Generate list of VPCs and save to variable to only query AWS once. If already made use existing list.
    if [ -z $Aws_Query ]; then
        Aws_Query=`aws ec2 --region ${REGION} describe-vpcs`
    fi
    # For every VPC in the region 
    for i in `echo $Aws_Query | jq ".Vpcs[] .VpcId"`; do
        echo ${i}
        
        aws ec2 delete-vpc --vpc-id ${i}
    done
    read test
}

## Parse file for VPC IDs
function Delete_File () {
    echo "Delete_File"
    for i in `cat input`; do
        echo ${i}
    done
    read test
}

## Catch all / Comma seperated list of VPC IDs ##
function Delete_CSL () {
    echo 'Delete_CSL'
    for i in $(echo $input | sed "s/,/ /g")
    do
        echo "$i"
    done

    read test
}

## The below functions handle deleting the resources inside a VPC. ##
## These functions should be kept in the order they are called to keep a good idea of the best order to process resources in to never end with a dependancy error. ##

function Delete_CloudFormation () {
    echo "Delete_CloudFormation"
}

function Delete_Beanstalk () {
    echo "Delete_Beanstalk"
}

function Delete_ECS_Cluster () {
    #https://docs.aws.amazon.com/cli/latest/reference/ecs/delete-cluster.html
    #All container instances must be deregistered before deleting cluster
    #Handle deregistration in this function as well.
    echo "Delete_ECS_Cluster"
}

function Delete_Instances () {
    echo "Delete Instance!"
}

function Delete_RDS_Clusters () {
    echo "Delete_RDS_Clusters"
}

function Delete_Route_Tables () {
    echo "Delete Route Tables"
}

function Detach_IGW () {
    echo "Detach_IGW"
}

function Delete_IGW () {
    echo "Delete_IGW"
}

function Detach_VPC_Gateway () {
    echo "Detach_VPC_Gateway"
}

function Delete_VPC_Gateway () {
    echo "Delete_VPC_Gateway"
}

# Will watch for error 255, if got send to remove rules
function Delete_Security_Groups () {
    echo "Delete_Security_Groups"
}

# The idea for this is if deleting an SG gets a dependacny error (error code 255) it is sent to this which describes all the rules, parses them and deletes them using jq to grab all values from the describe. #
function Security_Group_Rule_Delete () {
    echo "Security_Group_Rule_Delete"
}


##################################################################

## Find what method they used and direct to appropriate function. ##
if [[ ${input} == "All" ]]; then
    Delete_All
elif [[ -e ${input} ]]; then
    Delete_File
else
    Delete_CSL
fi
##################################################################
