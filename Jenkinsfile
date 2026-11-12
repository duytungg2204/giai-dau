pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    triggers {
        // Jenkins is local to this Windows machine, so poll GitHub once per minute.
        pollSCM('* * * * *')
    }

    parameters {
        string(
            name: 'DEPLOY_DIR',
            defaultValue: '',
            description: 'Folder containing the local .env and Compose deployment. Defaults to %USERPROFILE%/Downloads/cuoikytkpm-main/cuoikytkpm-main.'
        )
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate application') {
            steps {
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
                    def commit = (env.GIT_COMMIT ?: env.BUILD_NUMBER).take(12).toLowerCase()
                    env.BUILT_IMAGE = "giai-dau-app:${commit}"
                    bat "docker build --tag ${env.BUILT_IMAGE} ."
                }
            }
        }

        stage('Deploy with automatic rollback') {
            when {
                expression { isMainBranch() }
            }
            steps {
                script {
                    def deployDir = params.DEPLOY_DIR?.trim()
                    if (!deployDir) {
                        deployDir = "${env.USERPROFILE}\\Downloads\\cuoikytkpm-main\\cuoikytkpm-main"
                    }
                    withEnv(["APP_DEPLOY_DIR=${deployDir}", "APP_IMAGE=${env.BUILT_IMAGE}"]) {
                        bat 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\\deploy-docker-windows.ps1 -SourceDir "%WORKSPACE%" -DeployDir "%APP_DEPLOY_DIR%" -Image "%APP_IMAGE%"'
                    }
                }
            }
        }

        stage('Archive build files') {
            steps {
                archiveArtifacts artifacts: 'Jenkinsfile,package.json,package-lock.json,server.js,giai-dau.html,scripts/validate.js,scripts/deploy-docker-windows.ps1,Dockerfile,docker-compose.yml,.dockerignore', fingerprint: true
            }
        }
    }
}

def isMainBranch() {
    def branch = (env.BRANCH_NAME ?: env.GIT_BRANCH ?: '').tokenize('/').last()
    return branch == 'main'
}
