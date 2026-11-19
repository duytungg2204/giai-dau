// Pipeline CI/CD của dự án: kiểm tra mọi build, chỉ build và deploy Docker khi nhánh là main.
pipeline {
    agent any

    options {
        // Gắn thời gian vào log và tránh hai lần deploy chạy đè lên nhau.
        timestamps()
        disableConcurrentBuilds()
    }

    triggers {
        // Jenkins chạy local nên không nhận webhook từ GitHub; kiểm tra commit mới mỗi phút.
        pollSCM('* * * * *')
    }

    parameters {
        choice(
            name: 'DEPLOY_TARGET',
            choices: ['compose', 'kubernetes'],
            description: 'Nơi triển khai: compose trên máy hiện tại hoặc kubernetes qua kubectl.'
        )
        string(
            name: 'DEPLOY_DIR',
            defaultValue: '',
            description: 'Thư mục triển khai chứa .env; để trống sẽ dùng %USERPROFILE%/Downloads/cuoikytkpm-main/cuoikytkpm-main.'
        )
        string(
            name: 'K8S_NAMESPACE',
            defaultValue: 'giai-dau',
            description: 'Namespace Kubernetes đã có Deployment, Service và Secret cấu hình database.'
        )
        string(
            name: 'K8S_DEPLOYMENT',
            defaultValue: 'giai-dau-app',
            description: 'Tên Deployment Kubernetes cần cập nhật.'
        )
        string(
            name: 'K8S_CONTAINER',
            defaultValue: 'app',
            description: 'Tên container trong Deployment.'
        )
    }

    stages {
        stage('Checkout') {
            steps {
                // Lấy mã nguồn và Jenkinsfile từ SCM đã cấu hình trong job.
                checkout scm
            }
        }

        stage('Validate application') {
            steps {
                // Cài đúng dependency theo lockfile rồi chạy kiểm tra trước khi deploy.
                bat 'npm ci'
                bat 'npm run check'
            }
        }

        stage('Build Docker image') {
            when {
                expression { isMainBranch() }
            }
            steps {
                script {
                    // Gắn tag theo commit để truy vết image của từng bản build.
                    def commit = (env.GIT_COMMIT ?: env.BUILD_NUMBER).take(12).toLowerCase()
                    env.LOCAL_IMAGE = "giai-dau-app:${commit}"
                    bat "docker build --tag ${env.LOCAL_IMAGE} ."
                }
            }
        }

        stage('Deploy with Docker Compose') {
            when {
                expression { isMainBranch() && params.DEPLOY_TARGET == 'compose' }
            }
            steps {
                script {
                    // Dùng .env của máy triển khai; script sẽ kiểm tra sức khỏe và rollback nếu app lỗi.
                    def deployDir = params.DEPLOY_DIR?.trim()
                    if (!deployDir) {
                        deployDir = "${env.USERPROFILE}\\Downloads\\cuoikytkpm-main\\cuoikytkpm-main"
                    }
                    withEnv(["APP_DEPLOY_DIR=${deployDir}", "APP_IMAGE=${env.LOCAL_IMAGE}"]) {
                        bat 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\\deploy-docker-windows.ps1 -SourceDir "%WORKSPACE%" -DeployDir "%APP_DEPLOY_DIR%" -Image "%APP_IMAGE%"'
                    }
                }
            }
        }

        stage('Deploy to local Kubernetes') {
            when {
                expression { isMainBranch() && params.DEPLOY_TARGET == 'kubernetes' }
            }
            steps {
                script {
                    def deployDir = params.DEPLOY_DIR?.trim()
                    if (!deployDir) {
                        deployDir = "${env.USERPROFILE}\\Downloads\\cuoikytkpm-main\\cuoikytkpm-main"
                    }
                    withEnv([
                        "LOCAL_IMAGE=${env.LOCAL_IMAGE}",
                        "APP_DEPLOY_DIR=${deployDir}",
                        "K8S_NAMESPACE_VALUE=${params.K8S_NAMESPACE}",
                        "K8S_DEPLOYMENT_VALUE=${params.K8S_DEPLOYMENT}",
                        "K8S_CONTAINER_VALUE=${params.K8S_CONTAINER}"
                    ]) {
                        bat 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\\deploy-kubernetes-windows.ps1 -Image "%LOCAL_IMAGE%" -SourceDir "%WORKSPACE%" -DeployDir "%APP_DEPLOY_DIR%" -Namespace "%K8S_NAMESPACE_VALUE%" -Deployment "%K8S_DEPLOYMENT_VALUE%" -Container "%K8S_CONTAINER_VALUE%"'
                    }
                }
            }
        }

        stage('Archive build files') {
            steps {
                // Lưu các file quan trọng cùng build để tiện tra cứu lại.
                archiveArtifacts artifacts: 'Jenkinsfile,package.json,package-lock.json,server.js,giai-dau.html,scripts/validate.js,scripts/deploy-docker-windows.ps1,scripts/deploy-kubernetes-windows.ps1,scripts/setup-kubernetes-windows.ps1,k8s/*.yaml,Dockerfile,docker-compose.yml,.dockerignore', fingerprint: true
            }
        }
    }
}

def isMainBranch() {
    // Chuẩn hóa tên nhánh từ cả multibranch (main) và job thường (origin/main).
    def branch = (env.BRANCH_NAME ?: env.GIT_BRANCH ?: '').tokenize('/').last()
    return branch == 'main'
}
