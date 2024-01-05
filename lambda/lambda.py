import boto3
import base64
import json

ec2_client = boto3.client('ec2')
ecs_client = boto3.client('ecs')

def vpc_id_by_name(vpc_name):
    response = ec2_client.describe_vpcs(Filters=[{'Name': 'tag:Name', 'Values': [vpc_name]}])

    if 'Vpcs' in response and response['Vpcs']:
        return response['Vpcs'][0]['VpcId']
    else:
        raise ValueError(f"No VPC found with the name: {vpc_name}")

def subnets_for_vpc(vpc_name):
    vpc_id = vpc_id_by_name(vpc_name)
    response = ec2_client.describe_subnets(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])
    subnets = response['Subnets']
    subnets = list(map(lambda x: x['SubnetId'], subnets))

    return subnets

def handler(event, context):
    cluster_name = 'ShadowTrafficCluster'
    task_definition = 'ShadowTrafficTaskDefinition'
    subnets = subnets_for_vpc('ShadowTrafficVPC')

    response = ecs_client.list_tasks(
        cluster=cluster_name,
        desiredStatus='RUNNING'
    )

    running_tasks_count = len(response['taskArns'])

    # Throttle the amount of tasks if exposed to a public audience
    if running_tasks_count >= 2:
        return {
            'statusCode': 429
        }
    
    username = event['queryStringParameters']['username']
    password = event['queryStringParameters']['password']
    
    config = {
        'generators': [
            {
                'topic': 'customers',
                'key': {
                    'name': {
                        '_gen': 'string',
                        'expr': '#{Name.full_name}'
                    }
                }
            },
            {
                'topic': 'orders',
                'value': {
                    'orderId': {
                        '_gen': 'uuid'
                    },
                    'customerId': {
                        '_gen': 'lookup',
                        'topic': 'customers',
                        'path': [
                            'key',
                            'name'
                        ]
                    }
                }
            }
        ],
        'connections': {
            'dev-kafka': {
                'kind': 'kafka',
                'producerConfigs': {
                    'bootstrap.servers': event['queryStringParameters']['bootstrapServers'],
                    'security.protocol': 'SASL_SSL',
                    'sasl.jaas.config': f"org.apache.kafka.common.security.plain.PlainLoginModule required username='{username}' password='{password}';",
                    'sasl.mechanism': 'PLAIN',
                    'key.serializer': 'io.shadowtraffic.kafka.serdes.JsonSerializer',
                    'value.serializer': 'io.shadowtraffic.kafka.serdes.JsonSerializer'
                }
            }
        }
    }

    json_config = json.dumps(config)
    encoded_bytes = base64.b64encode(json_config.encode('utf-8'))
    encoded_config = encoded_bytes.decode('utf-8')

    task_override = {
        'containerOverrides': [
            {
                'name': 'ShadowTraffic',
                'command': [
                    '--config-base64', encoded_config, '--sample', '10000',
                ]
            }
        ]
    }

    response = ecs_client.run_task(
        cluster=cluster_name,
        taskDefinition=task_definition,
        launchType='FARGATE',
        overrides=task_override,
        count=1,
        networkConfiguration={
            'awsvpcConfiguration': {
                'subnets': subnets,
                'assignPublicIp': 'ENABLED'
            }
        }
    )
        
    return {
        'statusCode': 200
    }
