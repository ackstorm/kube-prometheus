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
        name: 'node-exporter-peer',
        resources+: {
          requests: { cpu: '50m' },
        },
      },
      blackboxExporter+: {
        name: 'balckbox-exporter-peer'
      },
      kubernetesControlPlane+: {
        name: 'kube-state-metrics-peer'
      }
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
      name: 'peer',
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
                then x { args+: [
                  "--metric-labels-allowlist=nodes=[node_pool,eks_amazonaws_com_nodegroup]" # Extract nodegroup labels from node
                  ] 
                }
                else x
                for x in super.containers
              ]
            }
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
          retention: "4h",
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
      }
    }
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
