CfhighlanderTemplate do

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'Ami', type: 'AWS::EC2::Image::Id'
    ComponentParam 'InstanceType', 't2.micro'
    ComponentParam 'KeyName', ''
    ComponentParam 'MinSize', 1
    ComponentParam 'MaxSize', 2
    ComponentParam 'DesiredSize', 1
    ComponentParam 'HealthCheckType', 'EC2', allowedValues: ['EC2','ELB']
    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
    ComponentParam 'TargetGroupARNs', ''
    ComponentParam 'LoadBalancerNames', ''

    if defined?(autoscaling)
      ComponentParam 'EnableScaling', 'false', allowedValues: ['true','false']
    end

  end

end
