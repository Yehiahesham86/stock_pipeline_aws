import boto3
from botocore.exceptions import ClientError

# Set to False to actually delete the roles
DRY_RUN = True

# Optional: Add role names you want to keep (e.g., your current admin/SSO/CI role)
EXCLUDE_ROLES = {
    "OrganizationAccountAccessRole",
}

iam = boto3.client("iam")

def delete_all_custom_roles():
    paginator = iam.get_paginator("list_roles")
    
    for page in paginator.paginate():
        for role in page["Roles"]:
            role_name = role["RoleName"]
            role_path = role["Path"]

            # Skip AWS service-linked roles and explicitly excluded roles
            if role_path.startswith("/aws-service-role/") or role_name in EXCLUDE_ROLES:
                print(f"[SKIP] {role_name} (Protected/Excluded)")
                continue

            if DRY_RUN:
                print(f"[DRY RUN] Would delete role: {role_name}")
                continue

            print(f"[DELETING] {role_name}...")
            try:
                # 1. Remove role from any Instance Profiles
                profiles = iam.list_instance_profiles_for_role(RoleName=role_name)["InstanceProfiles"]
                for profile in profiles:
                    iam.remove_role_from_instance_profile(
                        InstanceProfileName=profile["InstanceProfileName"],
                        RoleName=role_name
                    )

                # 2. Detach all Managed Policies
                attached_policies = iam.list_attached_role_policies(RoleName=role_name)["AttachedPolicies"]
                for policy in attached_policies:
                    iam.detach_role_policy(
                        RoleName=role_name,
                        PolicyArn=policy["PolicyArn"]
                    )

                # 3. Delete all Inline Policies
                inline_policies = iam.list_role_policies(RoleName=role_name)["PolicyNames"]
                for policy_name in inline_policies:
                    iam.delete_role_policy(
                        RoleName=role_name,
                        PolicyName=policy_name
                    )

                # 4. Delete the Role
                iam.delete_role(RoleName=role_name)
                print(f"[SUCCESS] Deleted {role_name}")

            except ClientError as e:
                print(f"[ERROR] Failed to delete {role_name}: {e}")

if __name__ == "__main__":
    delete_all_custom_roles()