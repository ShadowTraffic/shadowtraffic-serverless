import aws

vpc_name = 'ShadowTraffic VPC'
cluster_name = 'ShadowTrafficCluster'
task_definition = 'ShadowTrafficRunner'

max_tasks = 5

vpc_id = aws.vpc_id_by_name(vpc_name)
subnets = aws.subnets_for_vpc(vpc_id)
security_group = aws.security_group_for_vpc(vpc_id)

def handler(event, context):
    # Throttle the amount of tasks to control costs.
    if aws.check_throttle_request(cluster_name, max_tasks):
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

    return aws.submit_task(cluster_name, subnets, security_group, task_definition, config)
