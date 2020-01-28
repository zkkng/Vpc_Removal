#!/bin/bash
## This script can do serious damage to a company if misused.
## This script could irreversably cripple your infastructure if you are not careful ##

## Function Section ##
function Delete_All () {
    #echo "Delete_All"
    #Generate list of VPCs and save to variable to only query AWS once. If already made, use existing list.
    if [[ -z $Aws_Query ]]; then
        Aws_Query=`aws ec2 --region ${REGION} describe-vpcs`
    fi
    # For every VPC in the region 
    for i in `echo $Aws_Query | jq ".Vpcs[] .VpcId"`; do
        #echo ${i}                                                               #For testing only!
        VPC_List+="${i},"
    done
    #echo "VPC Finished List: ${VPC_List}"                                       #For testing only!
    VPC_Verify "${VPC_List::-1}"    # ::-1 removes the last comma
    read test #remove after testing
}

## Parse file for VPC IDs
function Delete_File () {
    #echo "Delete_File"
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
    #echo "VPC_Verify"
    VPC_List=${1}
    for i in $(echo ${VPC_List} | sed "s/,/ /g"); do
        #echo ${i}                                                               #Testing only
        i=`sed -e "s/[^ a-z0-9-]//g" <<<${i}`
        error=$( { aws ec2 describe-vpcs --vpc-id ${i} > /dev/null; } 2>&1 ) #sed -e "s/[^ a-z0-9-]//g" <<<${i} removes quotes
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
    #echo "Sanitized List ${Sanitized_Vpc_List::-1}"                             #Testing only
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
    Detach_VPN_Gateway "${VPC_List}"
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
        for i in `echo "${output}" | jq ".StackResourceSummaries[] .PhysicalResourceId"`; do 
            CFN_List+="${i} "
        done
        #list="${list}\n`echo -e "${output}" | jq ".StackResourceSummaries[] .PhysicalResourceId"`"  # Output only physical ID
        #list+="`echo -e "\n ${output}" | jq ".StackResourceSummaries[] .PhysicalResourceId"`"  # Output only physical ID
    done
    echo $CFN_List
}

## The below functions handle deleting the resources inside a VPC. ##
## These functions should be kept in the order they are called to keep a good idea of the best order to process resources in to never end with a dependancy error. ##
function CFN_Resource_Test () {
    echo "CFN_Resource_Test"
    Resource_ID=${1}
    #Need to add logic for generating a list of all CFN resource IDs once, then reference the output in this function.
    #Ask user if they want to skip CFN resource at beginning > generate and store list > reference list here
        if [[ ${CFN_List} == *${Resource_ID}* ]]; then
            Skip_Delete="True"
        else
            Skip_Delete="False"
        fi
    #return "${Skip_Delete}"
}
## Need to have an optional Cloudformation checker than will alert user if resources being deleted belong to a CFN stack.

function Delete_Instance () {
    ##### Consider making full list of instances then deleting all at once. Less API calls. ######
    ##### One If for CFN check then both ways just make a list and pass to a final delete whatever is in the list. #####
    #CFN returns instance IDs
    echo "Deleting Instances!"
    VPC_List=${1}
    for i in `aws ec2 describe-instances --filters "Name=vpc-id,Values=${VPC_List}" | jq '.Reservations[] .Instances[].InstanceId' | sed -e "s|[^ a-zA-Z0-9\:\/-]||g"`; do
        #if user said yes to cfn-check check if in list of cfn and skip if in
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List_Instance+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List_Instance+="${i} "
        fi
        # End CFN Snippet #
    done
    # for loop to delete individually to allow for individual error reporting? unless it handles deleting some but not all instances need to do testing
    for i in ${Delete_List_Instance}; do
        error=$( { aws ec2 terminate-instances --dry-run --instance-ids ${i} > /dev/null; } 2>&1 ) # Dry run for testing 
        if ! [[ ${?} == "0" ]]; then
            echo "Entry '${i}' FAILED with the following error: '${error}'"
        else
            echo "Deleted ${i}"
        fi
    done
}

function Delete_RDS_Instance () {
    echo "Delete_RDS_Instance"
    for i in `aws rds --region us-west-2 describe-db-instances | jq '.DBInstances[] .DBInstanceIdentifier'`; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List_RDS+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List_RDS+="${i} "
        fi
        # End CFN Snippet #
    done
}

function Delete_RDS_Cluster () {
    echo "Delete_RDS_Cluster"
    for i in `aws rds --region us-west-2 describe-db-clusters | jq '.DBClusters[] .DBClusterIdentifier'`; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List_Cluster+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List_Cluster+="${i} "
        fi
        # End CFN Snippet #
    done
}

function Detach_IGW () {
    echo "Detach_IGW"
    for i in echo "Placeholder"; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List+="${i} "
        fi
        # End CFN Snippet #
    done
}

function Delete_IGW () {
    echo "Delete_IGW"
    for i in echo "Placeholder"; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List+="${i} "
        fi
        # End CFN Snippet #
    done
    
}

function Delete_VPC_Endpoint () {
    echo "Delete_VPC_Endpoint"
    for i in echo "Placeholder"; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List+="${i} "
        fi
        # End CFN Snippet #
    done
}

function Delete_VPC_Peering () {
    echo "Delete_VPC_Peering"
    
}

#######This block will call eachother since they need to reference eachother's output ###
function Detach_VPN_Gateway () {
    echo "Detach_VPC_Gateway"
    for i in echo "Placeholder"; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List+="${i} "
        fi
        # End CFN Snippet #
    done
}

function Delete_VPN_Gateway () {
    echo "Delete_VPC_Gateway"
    #need to save this list for end
    for i in echo "Placeholder"; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List+="${i} "
        fi
        # End CFN Snippet #
    done
}

function Delete_VPN_connection () {
    #https://docs.aws.amazon.com/cli/latest/reference/ec2/delete-vpn-connection.html
    #Best practice Detach VPN Gateway >
    echo "Delete_VPN_connection"
}
######################################################################################

function Delete_NAT_Gateway () {
    echo "Delete_NAT_Gateway"
    for i in echo "Placeholder"; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List+="${i} "
        fi
        # End CFN Snippet #
    done
}

function Delete_Route_Table () {
    echo "Delete Route Tables"
    for i in echo "Placeholder"; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List+="${i} "
        fi
        # End CFN Snippet #
    done
}

function Detach_ENI () {
    echo "Detach_ENI"
    for i in echo "Placeholder"; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List+="${i} "
        fi
        # End CFN Snippet #
    done
}

function Delete_ENI () {
    echo "Delete_ENI"
    for i in echo "Placeholder"; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List+="${i} "
        fi
        # End CFN Snippet #
    done
}

# Any SG delete that returns an error that has (DependencyViolation) will be queued for rule delete script. Any other error will just fail and show error.
function Delete_Security_Group () {
    # CFN returns SG ID
    echo "Delete_Security_Group"
    for i in `aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_List}" | jq ".SecurityGroups[] .GroupId"`; do
        echo ${i}
        #CFN Snippet use to check all CFN resource! #
        if [[ ${CFN_Test} == "True" ]]; then
            CFN_Resource_Test "${i}"
            if [[ ${Skip_Delete} == "False" ]]; then
                Delete_List_SG+="${i} "
            else
                echo "${i} belongs to a CloudFormation template. Skipping."
            fi
        else
            Delete_List_SG+="${i} "
        fi
        # End CFN Snippet #
    done
    for i in ${Delete_List_SG}; do
        echo ${i}
        SG_ID=`sed -e "s/[^ a-z0-9-]//g" <<<${i}`
        error=$( { aws ec2 delete-security-group --dry-run --group-id ${SG_ID} > /dev/null; } 2>&1 )
        if ! [[ ${?} == "0" ]]; then
            if [[ ${error} == *"DependencyViolation"* ]]; then
                SG_Dependacy_Queue+="${SG_ID} "
            else
                echo "Entry '${SG_ID}' FAILED with the following error: '${error}'"
            fi
        else
            echo "Deleted ${SG_ID}"
        fi
    done
    if [[ -z ${SG_Dependacy_Queue} ]]; then
        Security_Group_Rule_Delete "${SG_Dependacy_Queue}"
    fi
}

# This function is a catastrophe and I am not smart enough to make it pretty =(
function Security_Group_Rule_Delete () {
    echo "Removing dependancies for all security groups that failed to delete... This may take a while depending on how many dependancies exist."
    SG_Dependacy_Queue=${1}
    for Sec_Id in ${SG_Dependacy_Queue}; do
        Remove_Rules_List=`aws ec2 describe-security-groups --filters "Name=ip-permission.group-id,Values=${Sec_Id}"`
        for x in $(seq 0 $(( `echo ${Remove_Rules_List} | jq ".SecurityGroups[]" | jq length` - 1 )) ); do                                                  # Gets sequence of number of seucrity groups for each SG
            for y in $(seq 0 $(( `echo ${Remove_Rules_List} | jq ".SecurityGroups[${x}] .IpPermissions"  | jq length` - 1 )) ); do                          # For each SG Gets sequence of number of rules
                Test_Val=`echo $Remove_Rules_List | jq ".SecurityGroups[${x}] .IpPermissions[${y}] .UserIdGroupPairs[0] | select(.GroupId=='${Sec_Id}')"`        # For Each rule check if it contains the SG-Id that is being deleted
                if ! [[ -z ${Test_Val} ]]; then                                                                                                             # If that value is found delete the rule
                    echo "Deleting rule"
                    GroupId=`echo $Remove_Rules_List | jq ".SecurityGroups[${x}] .GroupId" | sed -e "s/[^ a-z0-9-]//g"`
                    Protocol=`echo $Remove_Rules_List | jq ".SecurityGroups[${x}] .IpPermissions[${y}] .IpProtocol" | sed -e "s/[^ a-z0-9-]//g"`
                    FromPort=`echo $Remove_Rules_List | jq ".SecurityGroups[${x}] .IpPermissions[${y}] .FromPort" | sed -e "s/[^ a-z0-9-]//g"`
                    ToPort=`echo $Remove_Rules_List | jq ".SecurityGroups[${x}] .IpPermissions[${y}] .ToPort" | sed -e "s/[^ a-z0-9-]//g"`
                    aws ec2 revoke-security-group-ingress --group-id ${GroupId} --dry-run --ip-permissions "[{'IpProtocol': '${Protocol}', 'FromPort': ${FromPort}, 'ToPort': ${ToPort}, 'UserIdGroupPairs': [{'GroupId': '${Sec_Id}'}]}]"
                fi
            done
            for z in $( seq 0 $(( `echo ${Remove_Rules_List} | jq ".SecurityGroups[${Sec_Id}] .IpPermissionsEgress"  | jq length` - 1 )) ); do
                Test_Val=`echo $Remove_Rules_List | jq ".SecurityGroups[${x}] .IpPermissionsEgress[${z}] .UserIdGroupPairs[0] | select(.GroupId=='${Sec_Id}')"`  # For Each rule check if it contains the SG-Id that is being deleted
                if ! [[ -z ${Test_Val} ]]; then                                                                                                             # If that value is found delete the rule
                    echo "Deleting rule"
                    GroupId=`echo $Remove_Rules_List | jq ".SecurityGroups[${x}] .GroupId" | sed -e "s/[^ a-z0-9-]//g"`
                    Protocol=`echo $Remove_Rules_List | jq ".SecurityGroups[${x}] .IpPermissionsEgress[${z}] .IpProtocol" | sed -e "s/[^ a-z0-9-]//g"`
                    FromPort=`echo $Remove_Rules_List | jq ".SecurityGroups[${x}] .IpPermissionsEgress[${z}] .FromPort" | sed -e "s/[^ a-z0-9-]//g"`
                    ToPort=`echo $Remove_Rules_List | jq ".SecurityGroups[${x}] .IpPermissionsEgress[${z}] .ToPort" | sed -e "s/[^ a-z0-9-]//g"`
                    aws ec2 revoke-security-group-egress --group-id ${GroupId} --dry-run --ip-permissions "[{'IpProtocol': '${Protocol}', 'FromPort': ${FromPort}, 'ToPort': ${ToPort}, 'UserIdGroupPairs': [{'GroupId': '${Sec_Id}'}]}]"
                fi
            done
            # logic so I do not forget because i am dumdum
            # Remove_Rules_List is a list of OTHER SGs that reference the one that is being deleted
            # This for loop will sequence throguh .SecurityGroups[0-x]
            # We then need a count of all .ippermission and .egressrules sperately in each .SecurityGroups[0-x]
            # then for loop through each .IpPermissions[0-y] and use .UserIdGroupPairs[0] | select(.GroupId=="${i}")'
            # if it DOESNT return an error we take all values from that .IpPermissions or egress and use those values to delete the rule
            # Then we ALSO need to check VPC peering dependancies and decide if we are going to even try deleting those. Maybe check if the other VPC is in the same account and if it is then go delete the rules using same logic.
            # This is just an example command to select a rule with a specific SG-id ---- echo $Remove_Rules_List | jq '.SecurityGroups[] .IpPermissions[] .UserIdGroupPairs[0] | select(.GroupId=="sg-010817e281d9d1f42")'
        done
        
        
        
        ### All VPCs in the account should be checked so only need for VPC peering check would be to tell the user where the dependancies are. ###
        ### Since this isnt absolutely necessary I am leaving it unfinished for now. I am just too lazy ###
        
        Peering_Ref=`aws ec2 describe-security-group-references --group-id ${Sec_Id}`
        Peer_Count=`echo ${Peering_Ref} | | jq ".SecurityGroupReferenceSet" | jq length`
        if ((  ${Peer_Count} > 0 )); then
            echo "holder" 
            for a in $(seq 0 $(( ${Peer_Count} - 1 )) ); do
                Peer_Vpc_Id=`echo ${Peering_Ref} | jq ".SecurityGroupReferenceSet[${a}] .ReferencingVpcId" | sed -e "s/[^ a-z0-9-]//g"`
                Peer_Acc_Id=`aws ec2 describe-vpcs --vpc-id ${Peer_Vpc_Id} | jq ".Vpcs[0] .OwnerId"`
                =`aws ec2 describe-vpcs --vpc-id ${Peer_Vpc_Id} | jq ".Vpcs[0] .VpcPeeringConnectionId"`
                echo "The SG '${Sec_Id}' has a dependancy in a SG in VPC '${Peer_Vpc_Id}' which is located in the AWS account with ID '${Peer_Acc_Id}' via the peering connection '${Peering_Id}'. You will need to locate this dependancy, and remove in manually. This script does not support cross-account removals."
            done
        fi
        error=$( { aws ec2 delete-security-group --dry-run --group-id ${Sec_Id} > /dev/null; } 2>&1 )
        if ! [[ ${?} == "0" ]]; then
            echo "Entry '${SG_ID}' FAILED with the following error: '${error}'"
        else
            echo "Deleted ${SG_ID}"
        fi
    done
    #aws ec2 describe-security-groups --group-ids sg-028150dc2eb59ef6b  | jq ".SecurityGroups[] .IpPermissions[0]" #Have to use a seq for this. get group-id passed from first function.
    #aws ec2 revoke-security-group-ingress --group-id sg-028150dc2eb59ef6b --ip-permissions '[{"IpProtocol": "udp", "FromPort": 20000, "ToPort": 21000, "UserIdGroupPairs": [{"GroupId": "sg-06faf27bbd27832f4"}]}]'
}

#Delete peering connections here

function Delete_Subnet () {
    echo "Delete_Subnet"
    
}

function Delete_VPC () {
    echo "Delete_VPC"
    
}


##################################################################
## Warning section ##
RED='\033[0;31m' #Makes text RED
NC='\033[0m' #Makes text default, NC = No Color
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
tput clear # Doesnt matter in Python
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

## Optional CFN test section ##
echo "Would you like to skip any resource that is part of a CloudFormation stack?"
echo -n "Answer (y/n): "
read response
if [[ ${response} =~ ^([yY][eE][sS]|[yY])$ ]]; then
    CFN_Test="True"
    echo "Gathering list of all CFN resources. This may take a while depending on how many stacks are present in the region."
    CFN_List_Generate
fi
clear
#################################################################

## Make this optional later for bigger accounts. 
echo "Would you like generate a list of all VPCs in ${REGION}? y/n"
echo -n "Answer: "
read response
if [[ ${response} =~ ^([yY][eE][sS]|[yY])$ ]]; then
        clear
        echo "Generating a list of all VPCs found in the region. This make take a while depending on how many are in the account. "
        Aws_Query=`aws ec2 --region ${REGION} describe-vpcs`
        Vpc_Count=`echo $Aws_Query | jq '.Vpcs[]' | jq length | wc -l`
        for i in $(seq 1 "$Vpc_Count" ); do
            Vpc_Id_Temp=`echo $Aws_Query | jq ".Vpcs[$(( $i - 1 )) ] .VpcId"`
            echo ${i}". "${Vpc_Id_Temp}
            #declare vpc_${i}=${Vpc_Id_Temp}
            #Option_list=`echo "$Option_list\n${i}. ${Vpc_Id_Temp}"`
        done
else
    clear
fi
##################################################################

## Gets list of all VPCs in a region. Asks user which VPC they want to destory, or if they want to wipe them all.
## Choose method of deleting VPCs ##
echo -n """
Use one of the following methods to specify which VPCs you would like to delete.
1. Enter a list of comma sperated VPC IDs that you want to delete (e.g vpc-xxxxxxxxx,vpc-yyyyyyyyy,vpc-zzzzzzzzzz).
2. Enter the path to a file that contains the VPC IDs. Have one ID per line in this file.
3. Enter 'All' as a value and all VPCs in ${REGION} will be deleted.

Input: """
read input
clear
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
