local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'kube-prometheus/addons/all-namespaces.libsonnet') + 
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'kube-prometheus/addons/managed-cluster.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: 'observability-peer',
        name: 'peer',
        platform: 'gke'
      },
      prometheus+: {
        resources: {
          requests: { memory: '100Mi' },
        },
        enableFeatures: ["memory-snapshot-on-shutdown", "remote-write-receiver"],
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
                  "--metric-labels-allowlist=nodes=[node_pool,eks_amazonaws_com_nodegroup]" # Extract all labels from node
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
          externalLabels: {
            cluster: "${ENVIRONMENT}-${CLUSTER}",
            env: "${ENVIRONMENT}",
          },
          remoteWrite: [{
            url: '${OBSERVER_URL}/api/v1/push',
            headers: {
              "X-Scope-OrgID": "${ENVIRONMENT}-${CLUSTER}"
            }
          }],
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
{
  ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
  for name in std.filter((function(name) name != 'serviceMonitor' && name != 'prometheusRule'), std.objectFields(kp.prometheusOperator))
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
  for name in std.filter((function(name) name != 'prometheusRule' && name != 'prometheusRuleAwsVpcCni'), std.objectFields(kp.kubernetesControlPlane))
} +
{
  ['prometheus-' + name]: kp.prometheus[name]
  for name in std.filter((function(name) name != 'prometheusRule'), std.objectFields(kp.prometheus))
}
