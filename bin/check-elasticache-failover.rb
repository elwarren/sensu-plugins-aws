#!/usr/bin/env ruby

require "sensu-plugin/check/cli"
require "aws-sdk"

class CheckElastiCacheFailover < Sensu::Plugin::Check::CLI
  VERSION = "0.0.1"

  option(:profile,
    description: "Profile name of AWS shared credential file entry.",
    long:        "--profile PROFILE",
    short:       "-p PROFILE",
  )

  option(:region,
    description: "AWS region.",
    short:       "-r REGION",
    long:        "--region REGION",
  )

  option(:severity,
    description: "Critical or Warning.",
    short:       "-s SEVERITY",
    long:        "--severity SEVERITY",
    proc:        :intern.to_proc,
    default:     :critical,
  )

  option(:replication_group,
    description: "Replication group to check.",
    long:        "--replication-group ID",
    short:       "-g ID",
  )

  option(:node_group,
    description: "Node group to check.",
    long:        "--node-group ID",
    short:       "-n ID",
  )

  option(:primary_node,
    description: "Cluster name that should be primary.",
    long:        "--primary-node NAME",
    short:       "-c NAME",
  )

  def run
    replication_group = elasticache.client.describe_replication_groups.replication_groups.find do |g|
      g.replication_group_id == config[:replication_group]
    end

    unknown "Replication group not found." if replication_group.nil?

    node_group = replication_group.node_groups.find do |g|
      g.node_group_id == config[:node_group]
    end

    unknown "Node group not found." if node_group.nil?

    node = node_group.node_group_members.find do |n|
      n.cache_cluster_id == config[:primary_node]
    end

    unknown "Node not found." if node.nil?

    message = "Node `#{config[:primary_node]}` (in replication group `#{config[:replication_group]}`, node group `#{config[:node_group]}`) is "

    if node.current_role == "primary"
      message += "`primary`."
      ok message
    else
      message += "**not** `primary`."
      send config[:severity], message
    end
  end

  private

  def elasticache
    @elasticache ||= Aws::ElastiCache::Resource.new(aws_configuration)
  end

  def aws_configuration
    h = {}

    [:profile, :region].each do |option|
      h.update(option => config[option]) if config[option]
    end

    h.update(region: own_region) if h[:region].nil?
    h
  end

  def own_region
    @own_region ||= begin
      require "net/http"

      timeout 3 do
        Net::HTTP.get("169.254.169.254", "/latest/meta-data/placement/availability-zone").chop
      end
    rescue
      nil
    end
  end
end
