local kp =
  (import 'kube-prometheus/main.libsonnet') +
  (import 'kube-prometheus/addons/all-namespaces.libsonnet') + 
  (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  (import 'kube-prometheus/addons/managed-cluster.libsonnet') +
  // (import 'kube-prometheus/addons/pyrra.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: 'monitoring',
        platform: 'gke'
      },
      prometheus+: {
        namespaces: [],
        replicas: 2,
        enableFeatures: ["memory-snapshot-on-shutdown"],
        thanos: true,
        retention: "12h",
      },
    },
    kubeStateMetrics+: {
      deployment+: {
        spec+: {
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
    alertmanager+: {
      secret: {}, # Do not generate alertmanager config
      alertmanager+: {
        spec+: {
          replicas: 1,
          secrets: ["monitoring-basic-auth"],
          externalUrl: "https://${CLUSTER_INFO_MONITORING_URL}/alertmanager",
        }
      }
    },
    prometheus+: {
      prometheus+: {
        spec+: {
          enableAdminAPI: false,
          retention: "12h",
          externalUrl: "https://${CLUSTER_INFO_MONITORING_URL}/prometheus",
          additionalScrapeConfigs: {
            name: "additional-scrape-configs",
            key: "additional-scrape-configs-secret.yaml",
          },
          additionalAlertRelabelConfigs: {
            name: "additional-relabel-configs",
            key: "additional-relabel-configs-secret.yaml",
          },
          additionalAlertManagerConfigs: {
            name: "additional-alertmanager-config",
            key: "additional-alertmanager-config-secret.yaml",
          },
          externalLabels: {
            cluster: "${CLUSTER_INFO_PLATFORM_NAME}-${CLUSTER_INFO_ENVIRONMENT}",
            env: "${CLUSTER_INFO_ENVIRONMENT}",
          },
          storage: {
            volumeClaimTemplate: {
              apiVersion: 'v1',
              kind: 'PersistentVolumeClaim',
              spec: {
                accessModes: ['ReadWriteOnce'],
                resources: { 
                  requests: { 
                    storage: '20Gi' 
                  }
                },
                // storageClassName: 'ssd',
              }
            }
          },
          thanos: {
            version: "v0.30.2",
            objectStorageConfig: {
              key: "thanos-object-store-config-secret.yaml",
              name: "thanos-object-store-config",
            },
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
// { 'setup/pyrra-slo-CustomResourceDefinition': kp.pyrra.crd } +
// serviceMonitor and prometheusRule are separated so that they can be created after the CRDs are ready
{ 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
{ 'prometheus-operator-prometheusRule': kp.prometheusOperator.prometheusRule } +
{ 'kube-prometheus-prometheusRule': kp.kubePrometheus.prometheusRule } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['blackbox-exporter-' + name]: kp.blackboxExporter[name] for name in std.objectFields(kp.blackboxExporter) } +
// { ['pyrra-' + name]: kp.pyrra[name] for name in std.objectFields(kp.pyrra) if name != 'crd' } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['kubernetes-' + name]: kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane) }
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } // +
//{ ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) }
