import * as cdk from 'aws-cdk-lib';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';

import { Construct } from 'constructs';
import * as path from "path";

export class ShadowtrafficServerlessStack extends cdk.Stack {
    constructor(scope: Construct, id: string, props?: cdk.StackProps) {
        super(scope, id, props);

        const vpc = new ec2.Vpc(this, 'ShadowTrafficVPC', {
            vpcName: 'ShadowTrafficVPC',
            maxAzs: 1,
            subnetConfiguration: [
                {
                    cidrMask: 24,
                    name: 'ShadowTraffic Subnet',
                    subnetType: ec2.SubnetType.PUBLIC,
                    mapPublicIpOnLaunch: true
                }
            ]
        });

        const securityGroup = new ec2.SecurityGroup(this, 'ShadowTrafficSecurityGroup', {
            vpc,
            securityGroupName: 'ShadowTrafficSecurityGroup'
        });

        securityGroup.addEgressRule(ec2.Peer.anyIpv4(), ec2.Port.allTraffic(), 'Allow all outbound traffic');

        const cluster = new ecs.Cluster(this, 'ShadowTrafficCluster', {
            clusterName: 'ShadowTrafficCluster',
            vpc
        });
        
        const taskDefinition = new ecs.FargateTaskDefinition(this, 'ShadowTrafficTaskDefinition', {
            family: 'ShadowTrafficTaskDefinition'
        });

        const logging = new ecs.AwsLogDriver({
            streamPrefix: "ShadowTraffic"
        })
        
        const container = taskDefinition.addContainer('ShadowTraffic', {
            image: ecs.ContainerImage.fromRegistry('shadowtraffic/shadowtraffic:latest'),
            environment: {
                'LICENSE_ID': process.env.LICENSE_ID!,
                'LICENSE_EDITION': process.env.LICENSE_EDITION!,
                'LICENSE_EMAIL': process.env.LICENSE_EMAIL!,
                'LICENSE_EXPIRATION': process.env.LICENSE_EXPIRATION!,
                'LICENSE_ORGANIZATION': process.env.LICENSE_ORGANIZATION!,
                'LICENSE_SIGNATURE': process.env.LICENSE_SIGNATURE!
            },
            logging
        });

        const lambdaFunction = new lambda.Function(this, 'ShadowTrafficRunner', {
            runtime: lambda.Runtime.PYTHON_3_12,
            handler: 'lambda.handler',
            code: lambda.Code.fromAsset(path.join(__dirname, '/../lambda'))
        });

        const lambdaUrl = lambdaFunction.addFunctionUrl({
            authType: lambda.FunctionUrlAuthType.NONE,
        });

        lambdaFunction.role?.addManagedPolicy(
            iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonECS_FullAccess")
        );

        lambdaFunction.role?.addManagedPolicy(
            iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonEC2FullAccess")
        );

        new cdk.CfnOutput(this, 'LambdaUrl', {
            value: lambdaUrl.url
        });
    }
}
