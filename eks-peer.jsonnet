local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'kube-prometheus/addons/all-namespaces.libsonnet') + 
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'kube-prometheus/addons/managed-cluster.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: 'observability-peer',
        platform: 'eks',
      },
      prometheus+: {
        name: 'prometheus-peer',
        resources: {
          requests: { memory: '100Mi' },
        },
        enableFeatures: ["memory-snapshot-on-shutdown", "remote-write-receiver", "exemplar-storage"],
        # remote-write-received: allow opentelemetry to push metrics
      },
      nodeExporter+: {
        resources+: {
          requests: { cpu: '50m' },
        },
      },
      blackboxExporter+: {
      },
      kubernetesControlPlane+: {
      },
      prometheusOperator+: {
        name: "prometheus-operator-peer"
      },
    },
    priorityClass: {
      priorityClass: {
        apiVersion: 'v1',
        kind: 'ResourceQuota',
        metadata: {
          name: 'observability-peer',
          namespace: 'observability-peer',
        },
        spec: {
          hard: {
            pods: '1G',
          },
          scopeSelector: {
            matchExpressions: [
              {
              operator: 'In',
              scopeName: 'PriorityClass',
              values: [
                'system-node-critical',
                'system-cluster-critical'
              ]
              }
            ]
          }
        },
      },
    },
    kubeStateMetrics+: {
      serviceMonitor+: {
        spec+: {
          endpoints: [
            if x.port == "https-main"
            then x { metricRelabelings+: [
              {
                action: "replace",
                regex: "(.+)",
                replacement: "kube-state-metrics", # Avoid duplicate metrics with multiple replicas
                sourceLabels: ["__name__"],
                targetLabel: "instance"
              },
              {
                sourceLabels: ["label_node_pool"],
                regex: "(.+)",
                targetLabel: "node_pool"
              },
               {
                sourceLabels: ["eks_amazonaws_com_nodegroup"],
                regex: "(.+)",
                targetLabel: "node_pool"
              }
            ] 
            }
            else x
            for x in super.endpoints
          ]
        }
      },
      deployment+: {
        spec+: {
          replicas: 2,
          template+: {
            spec+: {
              containers: [
                if x.name == "kube-state-metrics"
                then x { 
                  args+: [
                    "--metric-labels-allowlist=nodes=[node_pool,eks_amazonaws_com_nodegroup]", # Extract nodegroup labels from node
                    "--resources=certificatesigningrequests,configmaps,cronjobs,daemonsets,deployments,endpoints,horizontalpodautoscalers,ingresses,jobs,leases,limitranges,mutatingwebhookconfigurations,namespaces,networkpolicies,nodes,persistentvolumeclaims,persistentvolumes,poddisruptionbudgets,pods,replicasets,replicationcontrollers,resourcequotas,secrets,services,statefulsets,storageclasses,validatingwebhookconfigurations,verticalpodautoscalers,volumeattachments" # add vpa
                  ] 
                }
                else x
                for x in super.containers
              ]
            }
          }
        }
      },
    },
    kubePrometheus+: {
      namespace+: {
        metadata+:{
          labels: {
            "goldilocks.fairwinds.com/enabled": "true" # Enable VPA recommendations
          }
        }
      }
    },
    prometheus+: {
      prometheus+: {
        spec+: {
          enableAdminAPI: false,
          alerting:: {},
          ruleSelector: {
            matchLabels: {
              role: "peer",
            }
          },
          replicas: 2,
          retention: "4d", # vpa recommender is configured for 4d pod history
          tsdb: {
            outOfOrderTimeWindow: "5m"
          },
          externalLabels: {
            cluster: "${ENVIRONMENT}-${CLUSTER}",
            env: "${ENVIRONMENT}",
          },
          remoteWrite: [{
            url: '${OBSERVER_URL}/api/v1/push',
            headers: {
              "X-Scope-OrgID": "${ENVIRONMENT}-${CLUSTER}"
            },
            queueConfig: {
              maxSamplesPerSend: 10000
            },
            sendExemplars: true,
            writeRelabelConfigs: [{
              sourceLabels: ["__name__"],
              targetLabel: "__name__",
              regex: "(.*)"
            }]
          }],
          additionalScrapeConfigs: {
            name: "additional-scrape-configs",
            key: "additional-scrape-configs.yaml",
          },
          additionalAlertRelabelConfigs: {
            name: "additional-relabel-configs",
            key: "additional-relabel-configs.yaml",
          },
          storage: {
            volumeClaimTemplate: {
              apiVersion: 'v1',
              kind: 'PersistentVolumeClaim',
              spec: {
                accessModes: ['ReadWriteOnce'],
                resources: { 
                  requests: { 
                    storage: '${VOLUME_SIZE}Gi' 
                  }
                },
                // storageClassName: 'ssd',
              }
            }
          },
          containers+: [{
              name: 'prometheus',
              startupProbe+: {
                failureThreshold: 120 # Extend recovery time for WAL
              }
          }]
        }
      },
    },
    nodeExporter+: {
      daemonset+: {
        spec+: {
          template+: {
            spec+: {
              containers: [
                if x.name == "node-exporter"
                then x { 
                  args+: [
                    # Reduce cardinality
                    "--no-collector.arp",
                    "--no-collector.ipvs",
                    "--no-collector.sockstat",
                    "--no-collector.softnet",
                    "--collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$"
                  ] 
                }
                else x
                for x in super.containers
              ]
            }
          },
        },
      },
      serviceMonitor+: {
        spec+: {
          endpoints: [
            if x.port == "https"
            then x { metricRelabelings+: [
              {
                sourceLabels: ["__name__"],
                action: "drop",
                regex: "node_(nf_conntrack_stat|netstat_.*6|timex_pps|network_carrie|network_iface|scrape).*",
              },
            ] 
            }
            else x
            for x in super.endpoints
          ]
        }
      }
    },
    kubernetesControlPlane+: {
      serviceMonitorApiserver+: {
        spec+: {
          endpoints: [
            if x.port == "https"
            then x { metricRelabelings+: [
              {
                sourceLabels: ["__name__"],
                action: "drop",
                regex: "(etcd_request_duration_seconds_buckt|apiserver_request_sli_duration_seconds_bucket|apiserver_request_slo_duration_seconds_bucket|apiserver_request_duration_seconds_bucket)",
              },
            ] 
            }
            else x
            for x in super.endpoints
          ]
        }
      }
    },
};

# Do not install prometheus rules
{ 'setup/0namespace-namespace': kp.kubePrometheus.namespace } +
{ ['setup/resourcequota-' + name]: kp.priorityClass[name] for name in std.objectFields(kp.priorityClass) } +
{
  ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
  for name in std.filter((function(name) name != 'prometheusRule'), std.objectFields(kp.prometheusOperator))
} +
{
  ['blackbox-exporter-' + name]: kp.blackboxExporter[name]
  for name in std.filter((function(name) name != 'prometheusRule'), std.objectFields(kp.blackboxExporter))
} +
{
  ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name]
  for name in std.filter((function(name) name != 'prometheusRule'), std.objectFields(kp.kubeStateMetrics))
} +
{
  ['node-exporter-' + name]: kp.nodeExporter[name]
  for name in std.filter((function(name) name != 'prometheusRule'), std.objectFields(kp.nodeExporter))
} +
{
  ['kubernetes-' + name]: kp.kubernetesControlPlane[name]
  for name in std.filter((function(name) name != 'prometheusRule'), std.objectFields(kp.kubernetesControlPlane))
} +
{
  ['prometheus-' + name]: kp.prometheus[name]
  for name in std.filter((function(name) name != 'prometheusRule'), std.objectFields(kp.prometheus))
}
