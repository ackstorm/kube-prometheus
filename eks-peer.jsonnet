local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'kube-prometheus/addons/all-namespaces.libsonnet') + 
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'kube-prometheus/addons/managed-cluster.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: 'observability',
        platform: 'eks'
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
                  "--metric-labels-allowlist=nodes=[*]" # Extract all labels from node
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
          ruleSelector:: {},
          replicas: 1, # the sample has been rejected because another sample with a more recent timestamp has already been ingeste
          retention: "4h",
          externalUrl: "https://${CLUSTER_INFO_MONITORING_URL}/prometheus",
          externalLabels: {
            cluster: "${CLUSTER_INFO_PLATFORM_NAME}-${CLUSTER_INFO_ENVIRONMENT}",
            env: "${CLUSTER_INFO_ENVIRONMENT}",
          },
          remoteWrite: [{
            url: 'http://mimir-nginx.observability.svc/api/v1/push',
            #headers: {
            #  "X-Scope-OrgID": "${CLUSTER_INFO_PLATFORM_NAME}-${CLUSTER_INFO_ENVIRONMENT}"
            #}
          }],
          storage: {
            volumeClaimTemplate: {
              apiVersion: 'v1',
              kind: 'PersistentVolumeClaim',
              spec: {
                accessModes: ['ReadWriteOnce'],
                resources: { 
                  requests: { 
                    storage: '50Gi' 
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
