import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.runtime.migration import MigrationContext
from sqlalchemy import create_engine, inspect

from app import models  # noqa: F401
from app.config import Settings
from app.db import Base
from app.main import create_app
from app.migrate import _config, current_revision, head_revision, require_up_to_date


def _migrated_engine(tmp_path):
    url = f"sqlite:///{tmp_path / 'm.db'}"
    engine = create_engine(url)
    cfg = _config()
    with engine.begin() as conn:
        cfg.attributes["connection"] = conn
        command.upgrade(cfg, "head")
    return engine


def test_migrations_build_exactly_the_schema_the_models_describe(tmp_path):
    engine = _migrated_engine(tmp_path)
    with engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    assert diff == [], "models changed without a migration: run alembic revision --autogenerate"
    assert current_revision(engine) == head_revision()


def test_there_is_a_single_linear_history():
    from alembic.script import ScriptDirectory
    assert len(ScriptDirectory.from_config(_config()).get_heads()) == 1


def test_downgrade_to_nothing_removes_the_tables(tmp_path):
    engine = _migrated_engine(tmp_path)
    cfg = _config()
    with engine.begin() as conn:
        cfg.attributes["connection"] = conn
        command.downgrade(cfg, "base")
    assert not set(inspect(engine).get_table_names()) - {"alembic_version"}


def test_prod_refuses_an_unmigrated_database(tmp_path):
    engine = create_engine(f"sqlite:///{tmp_path / 'empty.db'}")
    with pytest.raises(RuntimeError, match="alembic upgrade head"):
        require_up_to_date(engine)


def test_prod_start_check_passes_after_migrating(tmp_path):
    require_up_to_date(_migrated_engine(tmp_path))


def test_dev_still_creates_tables_itself():
    app = create_app(Settings(database_url="sqlite://"))
    assert "users" in inspect(app.state.engine).get_table_names()
