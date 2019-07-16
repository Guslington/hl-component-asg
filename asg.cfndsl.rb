CloudFormation do

  Condition 'DefinedLoadBalancers', FnNot(FnEquals(Ref('LoadBalancerNames'), ''))
  Condition 'DefinedTargetGroups', FnNot(FnEquals(Ref('TargetGroupARNs'), ''))
  Condition 'KeyNameSet', FnNot(FnEquals(Ref('KeyName'), ''))

  asg_tags = []
  asg_tags.push({ Key: 'Name', Value: FnSub("${EnvironmentName}-#{component_name}") })
  asg_tags.push({ Key: 'EnvironmentName', Value: Ref(:EnvironmentName) })
  asg_tags.push({ Key: 'EnvironmentType', Value: Ref(:EnvironmentType) })
  asg_tags.push(*tags.map {|k,v| {Key: k, Value: FnSub(v)}}).uniq { |h| h[:Key] } if defined? tags

  ingress = []
  security_group_rules.each do |rule|
    sg_rule = {
      FromPort: rule['from_port'],
      IpProtocol: rule['protocol'],
      ToPort: rule['to_port']
    }

    if rule['security_group_id']
      sg_rule['SourceSecurityGroupId'] = FnSub(rule['security_group_id'])
    else
      sg_rule['CidrIp'] = FnSub(rule['ip'])
    end
    if rule['desc']
      sg_rule['Description'] = FnSub(rule['desc'])
    end
    ingress << sg_rule
  end if defined?(security_group_rules)

  EC2_SecurityGroup "SecurityGroupASG" do
    VpcId Ref('VPCId')
    GroupDescription FnJoin(' ', [ Ref(:EnvironmentName), component_name, 'security group' ])
    SecurityGroupIngress ingress if ingress.any?
    SecurityGroupEgress ([
      {
        CidrIp: "0.0.0.0/0",
        Description: "outbound all for ports",
        IpProtocol: -1,
      }
    ])
    Tags tags
  end

  policies = []
  iam_policies.each do |name,policy|
    policies << iam_policy_allow(name,policy['action'],policy['resource'] || '*')
  end if defined? iam_policies

  Role('Role') do
    AssumeRolePolicyDocument service_role_assume_policy('ec2')
    Path '/'
    Policies(policies)
    Metadata({
      cfn_nag: {
        rules_to_suppress: [
          { id: 'F3', reason: 'future considerations to further define the describe permisions' }
        ]
      }
    })
  end

  InstanceProfile('InstanceProfile') do
    Path '/'
    Roles [Ref('Role')]
  end

  asg_tags.push({ Key: 'Role', Value: component_name })
  asg_tags.push({ Key: 'Name', Value: FnSub("${EnvironmentName}-#{component_name}-xx") })
  asg_tags.push(*instance_tags.map {|k,v| {Key: k, Value: FnSub(v)}}).uniq { |h| h[:Key] } if defined? instance_tags

  # Setup userdata string
  instance_userdata = "#!/bin/bash\nset -o xtrace\n"
  instance_userdata << userdata if defined? userdata
  instance_userdata << efs_mount if enable_efs
  instance_userdata << cfnsignal if defined? cfnsignal

  template_data = {
      SecurityGroupIds: [ Ref(:SecurityGroupASG) ],
      TagSpecifications: [
        { ResourceType: 'instance', Tags: asg_tags },
        { ResourceType: 'volume', Tags: asg_tags }
      ],
      UserData: FnBase64(FnSub(instance_userdata)),
      IamInstanceProfile: { Name: Ref(:InstanceProfile) },
      KeyName: FnIf('KeyNameSet', Ref('KeyName'), Ref('AWS::NoValue')),
      ImageId: Ref('Ami'),
      Monitoring: { Enabled: detailed_monitoring },
      InstanceType: Ref('InstanceType')
  }

  if defined? spot
    spot_options = {
      MarketType: 'spot',
      SpotOptions: {
        SpotInstanceType: (defined?(spot['type']) ? spot['type'] : 'one-time'),
        MaxPrice: FnSub(spot['price'])
      }
    }
    template_data[:InstanceMarketOptions] = FnIf('SpotPriceSet', spot_options, Ref('AWS::NoValue'))
  end

  if defined? volumes
    template_data[:BlockDeviceMappings] = volumes
  end

  EC2_LaunchTemplate(:LaunchTemplate) {
    LaunchTemplateData(template_data)
  }

  AutoScaling_AutoScalingGroup(:AutoScaleGroup) {
    AutoScalingGroupName name if defined? name
    if (defined? update_policy) && (update_policy['type'] == 'rolling')
      policy = {
        MaxBatchSize: update_policy['batch'],
        MinInstancesInService: FnIf('SpotPriceSet', 0, Ref('DesiredCapacity')),
        SuspendProcesses: %w(HealthCheck ReplaceUnhealthy AZRebalance AlarmNotification ScheduledActions)
      }
      policy[:PauseTime] = "PT#{update_policy['pause']}M" if update_policy.has_key? 'pause'
      UpdatePolicy(:AutoScalingRollingUpdate, policy)
    end

    DesiredCapacity Ref('DesiredSize')
    MinSize Ref('MinSize')
    MaxSize Ref('MaxSize')

    VPCZoneIdentifier Ref('SubnetIds')
    HealthCheckGracePeriod health_check_grace_period if defined? health_check_grace_period
    HealthCheckType Ref('HealthCheckType')

    LoadBalancerNames FnIf('DefinedLoadBalancers',
                            FnSplit(',', Ref('LoadBalancerNames')),
                            Ref('AWS::NoValue'))
    TargetGroupARNs FnIf('DefinedTargetGroups',
                            FnSplit(',', Ref('TargetGroupARNs')),
                            Ref('AWS::NoValue'))

    LaunchTemplate({
      LaunchTemplateId: Ref(:LaunchTemplate),
      Version: FnGetAtt(:LaunchTemplate, :LatestVersionNumber)
    })
  }

  if defined?(autoscaling)
    
    Condition 'IsScalingEnabled', FnEquals(Ref('EnableScaling'), 'true')
  
    Resource("CPUUtilizationAlarmHigh") {
      Condition 'IsScalingEnabled'
      Type 'AWS::CloudWatch::Alarm'
      Property('AlarmDescription', "Scale-up if CPUUtilization > #{autoscaling['cpu_high']}%")
      Property('MetricName','CPUUtilization')
      Property('Namespace','AWS/EC2')
      Property('Statistic', 'Maximum')
      Property('Period', '60')
      Property('EvaluationPeriods', '2')
      Property('Threshold', autoscaling['cpu_high'])
      Property('AlarmActions', [ Ref('ScaleUpPolicy') ])
      Property('Dimensions', [
        { Name: 'AutoScalingGroupName', Value: Ref('AutoScaleGroup') }
      ])
      Property('ComparisonOperator', 'GreaterThanThreshold')
    }

    Resource("CPUUtilizationAlarmLow") {
      Condition 'IsScalingEnabled'
      Type 'AWS::CloudWatch::Alarm'
      Property('AlarmDescription', "Scale-down if CPUUtilization < #{autoscaling['cpu_low']}%")
      Property('MetricName','CPUUtilization')
      Property('Namespace','AWS/EC2')
      Property('Statistic', 'Maximum')
      Property('Period', '60')
      Property('EvaluationPeriods', '2')
      Property('Threshold', autoscaling['cpu_low'])
      Property('AlarmActions', [ Ref('ScaleDownPolicy') ])
      Property('Dimensions', [
        { Name: 'AutoScalingGroupName', Value: Ref('AutoScaleGroup') }
      ])
      Property('ComparisonOperator', 'LessThanThreshold')
    }

    Resource("ScaleUpPolicy") {
      Condition 'IsScalingEnabled'
      Type 'AWS::AutoScaling::ScalingPolicy'
      Property('AdjustmentType', 'ChangeInCapacity')
      Property('AutoScalingGroupName', Ref('AutoScaleGroup'))
      Property('Cooldown','300')
      Property('ScalingAdjustment', autoscaling['scale_up_adjustment'])
    }

    Resource("ScaleDownPolicy") {
      Condition 'IsScalingEnabled'
      Type 'AWS::AutoScaling::ScalingPolicy'
      Property('AdjustmentType', 'ChangeInCapacity')
      Property('AutoScalingGroupName', Ref('AutoScaleGroup'))
      Property('Cooldown','300')
      Property('ScalingAdjustment', autoscaling['scale_down_adjustment'])
    }
  end

  Output('SecurityGroupASG') {
    Value(Ref('SecurityGroupASG'))
    Export FnSub("${EnvironmentName}-#{component_name}-SecurityGroup")
  }

end
