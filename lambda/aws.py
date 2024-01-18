import boto3
import json
import base64

ec2_client = boto3.client('ec2')
ecs_client = boto3.client('ecs')

def vpc_id_by_name(vpc_name):
    response = ec2_client.describe_vpcs(
        Filters=[
            {'Name': 'tag:Name', 'Values': [vpc_name]}
        ]
    )

    return response['Vpcs'][0]['VpcId']

def subnets_for_vpc(vpc_id):
    response = ec2_client.describe_subnets(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])
    subnets = response['Subnets']
    subnets = list(map(lambda x: x['SubnetId'], subnets))

    return subnets

def security_group_for_vpc(vpc_id):
    response = ec2_client.describe_security_groups(
        Filters=[
            {'Name': 'vpc-id', 'Values': [vpc_id]},
            {'Name': 'group-name', 'Values': ['ShadowTraffic Security Group']}
        ]
    )

    return response['SecurityGroups'][0]['GroupId']

def check_throttle_request(cluster_name, max_tasks):
    response = ecs_client.list_tasks(
        cluster=cluster_name,
        desiredStatus='RUNNING'
    )

    running_tasks_count = len(response['taskArns'])
    return running_tasks_count >= max_tasks

def submit_task(cluster_name, subnets, security_group, task_definition, config):
    json_config = json.dumps(config)
    encoded_bytes = base64.b64encode(json_config.encode('utf-8'))
    encoded_config = encoded_bytes.decode('utf-8')

    task_override = {
        'containerOverrides': [
            {
                'name': 'shadowtraffic',
                'command': [
                    '--config-base64', encoded_config, '--sample', '10000',
                ]
            }
        ]
    }
    
    return ecs_client.run_task(
        cluster=cluster_name,
        taskDefinition=task_definition,
        launchType='FARGATE',
        overrides=task_override,
        count=1,
        networkConfiguration={
            'awsvpcConfiguration': {
                'subnets': subnets,
                'securityGroups': [
                    security_group
                ],
                'assignPublicIp': 'ENABLED'
            }
        }
    )
