Generate an Ash resource using best practices for this project.

Arguments: $DOMAIN $RESOURCE_NAME

Steps:

1. Read docs/CODING_STANDARDS.md § Ash Resources
2. Read docs/DOMAIN_MODEL.md for the relevant domain
3. Run `mix ash.gen.resource $DOMAIN.$RESOURCE_NAME`
4. Add all attributes, relationships, and actions per the domain model
5. Add Ash Policies for all actions
6. Add AshJsonApi routes if this resource is API-exposed
7. Generate and run migration
8. Write tests for all actions
