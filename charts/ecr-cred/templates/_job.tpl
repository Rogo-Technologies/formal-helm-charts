{{- define "connector.ecrJob" }}
template:
  metadata:
    labels:
      {{- with .Values.podLabels }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
  spec:
    serviceAccountName: formal-ecr-secret-manager
    containers:
      - name: ecr-cred-helper
        {{- if .Values.image.digest }}
        image: "{{ .Values.image.repository }}@{{ .Values.image.digest }}"
        {{- else }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        {{- end }}
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 100m
            memory: 128Mi
        command:
          - /bin/sh
          - -c
          - |
            set -eu
            # Pin the kubectl version instead of resolving "latest" at runtime. The
            # previous `curl stable.txt` approach downloaded whatever the channel
            # currently pointed at, with no integrity check, and installed it into
            # /usr/local/bin -- so a compromised mirror, a DNS hijack, or a MITM on the
            # plaintext redirect could plant an arbitrary binary that then runs with
            # this job's ECR credentials in its environment.
            KUBECTL_VERSION="{{ .Values.kubectlVersion }}"
            KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
            curl -fsSLo /usr/local/bin/kubectl "${KUBECTL_URL}"
            curl -fsSLo /tmp/kubectl.sha256 "${KUBECTL_URL}.sha256"
            # The published checksum file is "<hash>  kubectl"; verify before use.
            echo "$(cat /tmp/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum -c -
            rm -f /tmp/kubectl.sha256
            chmod +x /usr/local/bin/kubectl
            TOKEN=$(aws ecr get-login-password --region {{ .Values.region }})
            kubectl delete secret formal-ecr-secret || true
            kubectl create secret docker-registry formal-ecr-secret \
              --docker-server={{ .Values.registryUrl }} \
              --docker-username=AWS \
              --docker-password="${TOKEN}"
        env:
          - name: AWS_ACCESS_KEY_ID
            valueFrom:
              secretKeyRef:
                name: {{ include "connector.fullname" . }}-ecr
                key: ecr-access-key-id
          - name: AWS_SECRET_ACCESS_KEY
            valueFrom:
              secretKeyRef:
                name: {{ include "connector.fullname" . }}-ecr
                key: ecr-secret-access-key
    restartPolicy: OnFailure
    {{- with .Values.tolerations }}
    tolerations:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}
