namespace :api_stats do
  desc "Display top user agents and IPs for the past 3 and 30 days"
  task summary: :environment do
    puts "\n" + "="*80
    puts "API Usage Statistics Summary"
    puts "="*80
    
    # Past 3 days
    puts "\nPast 3 Days:"
    puts "-"*40
    display_stats(3)
    
    # Past 30 days
    puts "\nPast 30 Days:"
    puts "-"*40
    display_stats(30)
    
    puts "\n" + "="*80
  end
  
  private
  
  def display_stats(days)
    user_agents = {}
    ips = {}
    
    # Collect data for the specified number of days
    days.times do |i|
      date = (Date.today - i).to_s
      
      # Collect user agents
      ua_key = "api_requests:#{date}"
      if REDIS.exists?(ua_key)
        REDIS.zrevrange(ua_key, 0, -1, with_scores: true).each do |agent, count|
          user_agents[agent] ||= 0
          user_agents[agent] += count.to_i
        end
      end
      
      # Collect IPs
      ip_key = "api_requests:ips:#{date}"
      if REDIS.exists?(ip_key)
        REDIS.zrevrange(ip_key, 0, -1, with_scores: true).each do |ip, count|
          ips[ip] ||= 0
          ips[ip] += count.to_i
        end
      end
    end
    
    # Sort and display top 10 user agents
    puts "\nTop User Agents:"
    if user_agents.empty?
      puts "  No user agent data available"
    else
      sorted_agents = user_agents.sort_by { |_, count| -count }.first(10)
      max_agent_length = sorted_agents.map { |agent, _| agent.length }.max || 0
      max_agent_length = [max_agent_length, 50].min # Cap at 50 chars for display
      
      sorted_agents.each_with_index do |(agent, count), index|
        display_agent = agent.length > 50 ? "#{agent[0..47]}..." : agent
        printf "  %2d. %-#{max_agent_length}s : %6d requests\n", index + 1, display_agent, count
      end
    end
    
    # Sort and display top 10 IPs
    puts "\nTop IP Addresses:"
    if ips.empty?
      puts "  No IP data available"
    else
      sorted_ips = ips.sort_by { |_, count| -count }.first(10)
      max_ip_length = sorted_ips.map { |ip, _| ip.length }.max || 0
      
      sorted_ips.each_with_index do |(ip, count), index|
        printf "  %2d. %-#{max_ip_length}s : %6d requests\n", index + 1, ip, count
      end
    end
    
    # Display totals
    puts "\nSummary:"
    puts "  Total unique user agents: #{user_agents.keys.count}"
    puts "  Total unique IPs: #{ips.keys.count}"
    puts "  Total API requests: #{user_agents.values.sum}"
  end
end