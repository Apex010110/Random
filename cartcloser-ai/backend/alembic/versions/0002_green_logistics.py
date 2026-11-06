"""green logistics extension

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-05 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa


revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('scenarios',
    sa.Column('id', sa.String(length=64), nullable=False),
    sa.Column('tenant_id', sa.String(length=64), nullable=False),
    sa.Column('name', sa.String(length=120), nullable=False),
    sa.Column('assumptions', sa.JSON(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['tenant_id'], ['tenants.id'], ),
    sa.PrimaryKeyConstraint('id'),
    )
    with op.batch_alter_table('scenarios', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_scenarios_tenant_id'), ['tenant_id'], unique=False)

    with op.batch_alter_table('audit_events', schema=None) as batch_op:
        batch_op.add_column(sa.Column('order_id', sa.String(length=64), nullable=True))
        batch_op.add_column(sa.Column('scenario_id', sa.String(length=64), nullable=True))
        batch_op.add_column(sa.Column('source', sa.String(length=16), nullable=False, server_default='simulated'))
        batch_op.create_index(batch_op.f('ix_audit_events_order_id'), ['order_id'], unique=False)

    with op.batch_alter_table('orders', schema=None) as batch_op:
        batch_op.add_column(sa.Column('fulfillment_status', sa.String(length=32), nullable=False, server_default='ready_to_dispatch'))
        batch_op.add_column(sa.Column('delivery_zone', sa.String(length=64), nullable=True))
        batch_op.add_column(sa.Column('address_redacted', sa.String(length=120), nullable=True))
        batch_op.add_column(sa.Column('scenario_id', sa.String(length=64), nullable=True))
        batch_op.add_column(sa.Column('size_question_resolved', sa.Boolean(), nullable=False, server_default=sa.false()))
        batch_op.add_column(sa.Column('cod_predispatch_confirmed', sa.Boolean(), nullable=False, server_default=sa.false()))
        batch_op.add_column(sa.Column('had_failed_attempt', sa.Boolean(), nullable=False, server_default=sa.false()))
        batch_op.add_column(sa.Column('ever_delivered', sa.Boolean(), nullable=False, server_default=sa.false()))
        batch_op.add_column(sa.Column('was_held', sa.Boolean(), nullable=False, server_default=sa.false()))
        batch_op.add_column(sa.Column('delivery_consolidation_selected', sa.Boolean(), nullable=False, server_default=sa.false()))
        batch_op.create_index(batch_op.f('ix_orders_fulfillment_status'), ['fulfillment_status'], unique=False)
        batch_op.create_index(batch_op.f('ix_orders_scenario_id'), ['scenario_id'], unique=False)
        batch_op.create_foreign_key('fk_orders_scenario_id', 'scenarios', ['scenario_id'], ['id'])


def downgrade() -> None:
    with op.batch_alter_table('orders', schema=None) as batch_op:
        batch_op.drop_constraint('fk_orders_scenario_id', type_='foreignkey')
        batch_op.drop_index(batch_op.f('ix_orders_scenario_id'))
        batch_op.drop_index(batch_op.f('ix_orders_fulfillment_status'))
        batch_op.drop_column('delivery_consolidation_selected')
        batch_op.drop_column('was_held')
        batch_op.drop_column('ever_delivered')
        batch_op.drop_column('had_failed_attempt')
        batch_op.drop_column('cod_predispatch_confirmed')
        batch_op.drop_column('size_question_resolved')
        batch_op.drop_column('scenario_id')
        batch_op.drop_column('address_redacted')
        batch_op.drop_column('delivery_zone')
        batch_op.drop_column('fulfillment_status')

    with op.batch_alter_table('audit_events', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_audit_events_order_id'))
        batch_op.drop_column('source')
        batch_op.drop_column('scenario_id')
        batch_op.drop_column('order_id')

    op.drop_index('ix_scenarios_tenant_id', table_name='scenarios')
    op.drop_table('scenarios')
