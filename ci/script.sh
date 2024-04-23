#!/bin/bash
set -euo pipefail

docker_image_build_name="${DOCKER_IMAGE_BUILD_NAME:-}"
dockerfile_name="${DOCKER_FILE_NAME:-}"
docker_hub_org="${DOCKER_HUB_ORG:-horizenlabs}"

github_token="${GITHUB_TOKEN:-}"
docker_writer_password="${DOCKER_WRITER_PASSWORD:-}"
docker_writer_username="${DOCKER_WRITER_USERNAME:-}"

is_a_release="${IS_A_RELEASE:-false}"
prod_release="${PROD_RELEASE:-false}"
dev_release="${DEV_RELEASE:-false}"

workdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"

echo "=== Workdir: ${workdir} ==="
command -v docker &> /dev/null

# Functions
function fn_die() {
  echo -e "$1" >&2
  exit "${2:-1}"
}

# checking if GITHUB_TOKEN is set
echo "=== Checking if GITHUB_TOKEN is set ==="
if [ -z "${github_token:-}" ]; then
  fn_die "GITHUB_TOKEN variable is not set. Exiting ..."
fi

echo "=== Checking if DOCKER_WRITER_PASSWORD is set ==="
if [ -z "${docker_writer_password:-}" ]; then
  fn_die "DOCKER_WRITER_PASSWORD variable is not set. Exiting ..."
fi

echo "=== Checking if DOCKER_WRITER_USERNAME is set ==="
if [ -z "${docker_writer_username:-}" ]; then
  fn_die "DOCKER_WRITER_USERNAME variable is not set. Exiting ..."
fi

docker_tag=""
if [ "${is_a_release}" = "true" ]; then
  docker_tag="${TRAVIS_TAG}"
fi

# Building and publishing docker image
if [ -n "${docker_tag:-}" ]; then
  echo "" && echo "=== Building Docker image ===" && echo ""

  docker build -f "ci/${dockerfile_name}" -t "${docker_image_build_name}:${docker_tag}" .

  # Publishing to DockerHub
  echo "" && echo "=== Publishing Docker image(s) on Docker Hub ===" && echo ""
  echo "${docker_writer_password}" | docker login -u "${docker_writer_username}" --password-stdin

  # Docker image(s) tags for PROD vs DEV release
  if [ "${prod_release}" = "true" ]; then
    publish_tags=("${docker_tag}" "latest")
  elif [ "${dev_release}" = "true" ]; then
    publish_tags=("${docker_tag}")
  fi

  for publish_tag in "${publish_tags[@]}"; do
    echo "" && echo "Publishing docker image: ${docker_image_build_name}:${publish_tag}"
    docker tag "${docker_image_build_name}:${docker_tag}" "index.docker.io/${docker_hub_org}/${docker_image_build_name}:${publish_tag}"
    docker push "index.docker.io/${docker_hub_org}/${docker_image_build_name}:${publish_tag}"
  done
else
  echo "" && echo "=== The build did NOT satisfy RELEASE build requirements. Docker image(s) was(were) NOT created/published ===" && echo ""
fi

# If a production release build Generate GitHub Release
if [ "${is_a_release}" = "true" ] && [ "${prod_release}" = "true" ]; then
  # Release notes to Github
  echo "" && echo "=== Generating GitHub Release ${TRAVIS_TAG} for ${TRAVIS_REPO_SLUG} ===" && echo ""
  curl -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token ${github_token}" https://api.github.com/repos/"${TRAVIS_REPO_SLUG}"/releases -d "{\"tag_name\":\"${TRAVIS_TAG}\",\"generate_release_notes\":true}"
fi


######
# The END
######
echo "" && echo "=== Done ===" && echo ""

exit 0
