"""CLI: python -m app.cli [migrate|seed|reset|openapi]"""
import json
import sys


def main(argv: list[str]) -> None:
    cmd = argv[1] if len(argv) > 1 else "help"
    if cmd == "migrate":
        from alembic import command
        from alembic.config import Config

        command.upgrade(Config("alembic.ini"), "head")
    elif cmd in ("seed", "reset"):
        from app.db.session import SessionLocal
        from app.models.entities import Tenant
        from app.services.seed import reset_and_seed

        db = SessionLocal()
        try:
            if cmd == "reset" or db.get(Tenant, "urbanthread-pk") is None:
                reset_and_seed(db)
                print("Demo data seeded (UrbanThread PK, fictional).")
            else:
                print("Already seeded. Use 'reset' to start over.")
        finally:
            db.close()
    elif cmd == "openapi":
        from app.main import create_app

        print(json.dumps(create_app(run_scheduler=False).openapi(), indent=2))
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv)
