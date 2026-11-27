-- Version 0.3.0 asks for the age confirmation (docs/MINIMUM-AGE-PLAN.md 4a). It is out on both platforms, so older builds now
-- show the update screen in the social parts; their logbook keeps working.
update public.app_config set min_version_ios = '0.3.0', min_version_android = '0.3.0';
