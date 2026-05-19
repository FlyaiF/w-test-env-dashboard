package db

import "test-env-dashboard/go_sidecar/model"

type ConfigRepository interface {
	ListEnvs(search string, page, pageSize int) ([]model.EnvInfo, int, error)
	ListAllEnvs() ([]model.EnvInfo, error)
	GetEnv(id int64) (model.EnvInfo, error)
	CreateEnv(e model.EnvInfo) error
	UpdateEnv(id int64, e model.EnvInfo) error
	DeleteEnv(id int64) error
	PublishCollectedEnvInfo(item model.RuntimePublishItem) error
}

type OracleConfigRepository struct{}

var configRepository ConfigRepository = OracleConfigRepository{}

func SetConfigRepository(repo ConfigRepository) {
	configRepository = repo
}

func ListEnvs(search string, page, pageSize int) ([]model.EnvInfo, int, error) {
	return configRepository.ListEnvs(search, page, pageSize)
}

func ListAllEnvs() ([]model.EnvInfo, error) {
	return configRepository.ListAllEnvs()
}

func GetEnv(id int64) (model.EnvInfo, error) {
	return configRepository.GetEnv(id)
}

func CreateEnv(e model.EnvInfo) error {
	return configRepository.CreateEnv(e)
}

func UpdateEnv(id int64, e model.EnvInfo) error {
	return configRepository.UpdateEnv(id, e)
}

func DeleteEnv(id int64) error {
	return configRepository.DeleteEnv(id)
}

func PublishCollectedEnvInfo(item model.RuntimePublishItem) error {
	return configRepository.PublishCollectedEnvInfo(item)
}
