# Curriculum bundle

The content the stand-alone mode ships with (#266): `manifest.json` plus one
JSON file per container (`goals`, `content`, `modules`, `instructions`,
`translations`, `config`, `questions`), exported from the live content by
`tooling/curriculum/export_bundle.py` (#265). The format and what may leave
are documented in that script. `manifest.json` holds the content version
(`contentVersion`), the export date and the number of docs per container.
The school mode never reads this folder.

## Refreshing it

1. `python tooling/curriculum/export_bundle.py diff` shows what changed live
   since this bundle, per goal, lesson, prompt section, translation and
   question. It only reads.
2. Look through the diff, then
   `python tooling/curriculum/export_bundle.py export` writes this folder.
   It stops without writing when anything looks like a key. An export whose
   content did not change leaves the folder as it is.
3. Run `python -m unittest discover -s tooling/curriculum/tests` and
   `flutter test test/core/curriculum_bundle_test.dart`: both check the
   bundle in this folder.
4. Commit the folder before the release.

The app compares `contentVersion` with the version it loaded last and loads
a new bundle at the next start.
