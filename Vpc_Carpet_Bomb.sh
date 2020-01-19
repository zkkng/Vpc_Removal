#!/bin/bash
## This script can do serious damage to a company if misused.
## This script could irreversably cripple your infastructure if you are not careful ##

## Function Section ##
function Delete_All () {
    echo "Delete_All"
    #Generate list of VPCs and save to variable to only query AWS once. If already made, use existing list.
    if [[ -z $Aws_Query ]]; then
        Aws_Query=`aws ec2 --region ${REGION} describe-vpcs`
    fi
    # For every VPC in the region 
    for i in `echo $Aws_Query | jq ".Vpcs[] .VpcId"`; do
        echo ${i}                                                               #For testing only!
        VPC_List+="${i},"
    done
    echo "VPC Finished List: ${VPC_List}"                                       #For testing only!
    VPC_Verify "${VPC_List::-1}"    # ::-1 removes the last comma
    read test #remove after testing
}

## Parse file for VPC IDs
function Delete_File () {
    echo "Delete_File"
    file=${1}
    while IFS= read -r i; do
        echo ${i}
        VPC_List+="${i},"
    done < "${file}"
    VPC_Verify "${VPC_List::-1}" # ::-1 removes the last comma
    read test #remove after testing
}

## Catch all / Comma seperated list of VPC IDs ##
## Should just directly pass input to VPC_Verify since should already be CSV list
function Delete_CSL () {
    input=${1}
    echo 'Delete_CSL'
    VPC_Verify "${input}"
    read test #remove after testing
}

## Function here to verify all VPC entered are valid in the entered region. ##
## Catch any invalid entries
function VPC_Verify () {
    echo "VPC_Verify"
    VPC_List=${1}
    for i in $(echo ${VPC_List} | sed "s/,/ /g"); do
        echo ${i}                                                               #Testing only
        i=`sed -e "s/[^ a-z0-9-]//g" <<<${i}`
        error=$( { aws ec2 describe-vpcs --vpc-id ${i} > outfile; } 2>&1 ) #sed -e "s/[^ a-z0-9-]//g" <<<${i} removes quotes
        if ! [[ ${?} == "0" ]]; then
            echo "Entry '${i}' FAILED with the following error: '${error}'" 
            Verify_Fail="true"
        else
            Sanitized_Vpc_List+="${i},"
        fi
    done
    if [[ -v $Verify_Fail ]]; then
        echo "One or more of your entries failed. Would you like to exit the script to fix this? (Y/n)"
        echo -n "Answer: "
        read cont
        if ! [[ ${cont} =~ ^([yY][eE][sS]|[yY])$ ]]; then
            clear
            echo "VPC IDs incorrectly entered. User chose to exit."
            exit 101
        fi
    fi
    if [[ -z ${Sanitized_Vpc_List} ]]; then
        clear
        echo "There were no valid entries! Exiting."
        exit 100
    fi
    echo "Sanitized List ${Sanitized_Vpc_List::-1}"                             #Testing only
    read test
    Distribute_Delete "${Sanitized_Vpc_List::-1}" # ::-1 removes trailing space
}

## Function to pass VPC IDs to all the delete functions ##
## Considering adding GNU parallel to speed up process.
## Parelle idea > get all resource IDs in one command then parallel the delete commands.
function Distribute_Delete () {
    VPC_List=${1}
    Delete_Instance "${VPC_List}"
    Delete_RDS_Cluster "${VPC_List}"
    Detach_IGW "${VPC_List}"
    Delete_IGW "${VPC_List}"
    Delete_VPC_Endpoint "${VPC_List}"
    Detach_VPC_Gateway "${VPC_List}"
    Delete_VPC_Gateway "${VPC_List}"
    Delete_NAT_Gateway "${VPC_List}"
    Delete_Route_Table "${VPC_List}"
    Detach_ENI "${VPC_List}"
    Delete_ENI "${VPC_List}"
    Delete_Security_Group "${VPC_List}"
    Delete_Subnet "${VPC_List}"
    Delete_VPC "${VPC_List}"
}

function CFN_List_Generate () {
    #Checks all stacks in the specified region and makes one huge list of the resource IDs for all stacks.
    echo "CFN_List_Generate"
    for i in `aws cloudformation list-stacks --region ${REGION} --stack-status-filter CREATE_COMPLETE | jq  '.StackSummaries[] .StackId' | sed -e "s|[^ a-zA-Z0-9\:\/-]||g"`; do # Gets list of all CFN stack ARNs in REGION and removes all extra characters
        output=`aws cloudformation list-stack-resources --region ${REGION} --stack-name ${i}` # Stores output of listing all stack resources
        echo -e "${output}\n" | jq ".StackResourceSummaries[] .PhysicalResourceId"  # Output only physical ID
        
    done
}

## The below functions handle deleting the resources inside a VPC. ##
## These functions should be kept in the order they are called to keep a good idea of the best order to process resources in to never end with a dependancy error. ##
function CFN_Resource_Test () {
    echo "CFN_Resource_Test"
    #Need to add logic for generating a list of all CFN resource IDs once, then reference the output in this function.
    #Ask user if they want to skip CFN resource at beginning > generate and store list > reference list here
        if [[ ${CFN_Resource_List} == *${Resource_ID}* ]]; then
            echo "${Resource_ID} belongs to a CloudFormation template. Skipping."
            Skip_Delete="True"
        else
            Skip_Delete="False"
        fi
}
## Need to have an optional Cloudformation checker than will alert user if resources being deleted belong to a CFN stack.

function Delete_Instance () {
    #CFN returns instance IDs
    echo "Deleting Instances!"
    VPC_List=${1}
    for i in `aws ec2 describe-instances --filters "Name=vpc-id,Values=${VPC_List}" | jq '.Reservations[] .Instances[].InstanceId'`; do
        #if user said yes to cfn-check check if in list of cfn and skip if in
        #else delete immediately
        echo ${i}                                                               #Testing only
    done
}

function Delete_RDS_Cluster () {
    echo "Delete_RDS_Cluster"
    for i in `aws rds --region us-west-2 describe-db-clusters | jq '.DBClusters[] .DBClusterIdentifier'`; do
        echo ${i}
    done
}

function Delete_RDS_Instance () {
    echo "Delete_RDS_Instance"
    for i in `aws rds --region us-west-2 describe-db-instances | jq '.DBInstances[] .DBInstanceIdentifier'`; do
        echo ${i}
    done
}

function Detach_IGW () {
    echo "Detach_IGW"
    
}

function Delete_IGW () {
    echo "Delete_IGW"
    
}

function Delete_VPC_Endpoint () {
    echo "Delete_VPC_Endpoint"
    
}

function Detach_VPC_Gateway () {
    echo "Detach_VPC_Gateway"
    
}

function Delete_VPC_Gateway () {
    echo "Delete_VPC_Gateway"
    
}

function Delete_NAT_Gateway () {
    echo "Delete_NAT_Gateway"
    
}

function Delete_Route_Table () {
    echo "Delete Route Tables"
    
}

function Detach_ENI () {
    echo "Detach_ENI"
    
}

function Delete_ENI () {
    echo "Delete_ENI"
    
}

# Will watch for error 255, if got send to remove rules
function Delete_Security_Group () {
    # CFN returns SG ID
    echo "Delete_Security_Group"
    
}

# The idea for this is if deleting an SG gets a dependacny error (error code 255) it is sent to this which describes all the rules, parses them and deletes them using jq to grab all values from the describe. #
function Security_Group_Rule_Delete () {
    echo "Security_Group_Rule_Delete"
    
}

function Delete_Subnet () {
    echo "Delete_Subnet"
    
}

function Delete_VPC () {
    echo "Delete_VPC"
    
}

##################################################################
## Warning section ##
RED='\033[0;31m'
NC='\033[0m'
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
    echo -en """${NC}This script is dangerous! It can damage your infastructure in irreversible ways if you are not careful!
This script will attempt to delete all VPC IDs that you input, or wipeout all VPCs in a region.
If you run this script carelessly, or without permission you could take an entire company.
There will be one final confirmation before any asset is deleted. Think carefully before continuing.
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
    echo -n "Enter the region the VPC(s) you want to delete are in (e.g us-west-2): "
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
if [[ ${response} =~ ^([yY][eE][sS]|[yY])$ ]]; then
        Aws_Query=`aws ec2 --region ${REGION} describe-vpcs`
        Vpc_Count=`echo $Aws_Query | jq '.Vpcs[]' | jq length | wc -l`
        echo "Generating a list of all VPCs found in the region. This make take a while depending on how many are in the account. "
        for i in $(seq 1 "$Vpc_Count" ); do
            Vpc_Id_Temp=`echo $Aws_Query | jq ".Vpcs[$(( $i - 1 )) ] .VpcId"`
            echo ${i}". "${Vpc_Id_Temp}
            #declare vpc_${i}=${Vpc_Id_Temp}
            #Option_list=`echo "$Option_list\n${i}. ${Vpc_Id_Temp}"`
        done
fi
##################################################################

## 
echo "Would you like to skip any resource that is part of a CloudFormation stack?"
echo -n "Answer (y/n): "
read response
if [[ ${response} =~ ^([yY][eE][sS]|[yY])$ ]]; then
    CFN_Test="True"
fi

## Choose method of deleting VPCs ##
echo -n """
Use one of the following methods to specify which VPCs you would like to delete.
1. Enter a list of comma sperated VPC IDs that you want to delete (e.g vpc-xxxxxxxxx,vpc-yyyyyyyyy,vpc-zzzzzzzzzz).
2. Enter the path to a file that contains the VPC IDs. Have one ID per line in this file.
3. Enter "All" as a value and all VPCs in ${REGION} will be deleted.

Input: """
read input
##################################################################


## Find what method they used and direct to appropriate function. ##
if [[ ${input} == "All" ]]; then
    Delete_All 
elif [[ -e ${input} ]]; then
    Delete_File "${input}"
else
    Delete_CSL "${input}"
fi
##################################################################
