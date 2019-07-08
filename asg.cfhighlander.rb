CfhighlanderTemplate do

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
    ComponentParam 'Ami', type: 'AWS::EC2::Image::Id'
    ComponentParam 'InstanceType'
    ComponentParam 'KeyName'
    ComponentParam 'MinSize'
    ComponentParam 'MaxSize'
    ComponentParam 'DesiredSize'
    ComponentParam 'HealthCheckType', 'EC2', allowedValues: ['EC2','ELB']
    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
    ComponentParam 'TargetGroupARNs'
    ComponentParam 'LoadBalancerNames'

    if defined?(autoscale)
      ComponentParam 'EnableScaling', 'false', allowedValues: ['true','false']
    end

  end

end
