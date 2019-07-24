def generate_security_group_rules(security_group_rules,ip_blocks={})
  rules = []
  security_group_rules.each do |rule|
    ips = []
    
    if rule.has_key?('ip_blocks')
      ip_blocks.each { |name,block| (ips.concat(block)).uniq }
    elsif rule.has_key?('ip')
      ips.push(rule['ip'])  
    end
    
    sg_rule = {}
    sg_rule[:FromPort] = rule['from']
    sg_rule[:IpProtocol] = (rule.has_key?('protocol') ? rule['protocol'] : 'TCP')
    sg_rule[:ToPort] = (rule.has_key?('to') ? rule['to'] : rule['from'])
    sg_rule[:Description] = FnSub(rule['desc']) if rule.has_key?('desc')
    
    if ips.any?
      ips.each do |ip|
        sg_rule[:CidrIp] = ip
        rules << sg_rule
      end
    else
      sg_rule[:SourceSecurityGroupId] = FnSub(rule['security_group_id'])
      rules << sg_rule
    end
  end
  return rules
end