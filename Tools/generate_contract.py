import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
schema = json.loads((ROOT / 'Schemas/course.schema.json').read_text())


def declaration(name, definition):
    properties = definition['properties']
    required = set(definition['required'])
    lines = [f'public struct {name}: Codable, Sendable {{']
    parameters = []
    for key, value in properties.items():
        kind = {'string': 'String', 'integer': 'Int', 'array': '[String]'}[value['type']]
        if key == 'sections':
            kind = '[CourseSection]'
        if key == 'kind':
            kind = 'DocumentKind'
        optional = key not in required
        lines.append(f'    public let {key}: {kind}{"?" if optional else ""}')
        parameters.append(f'{key}: {kind}{"? = nil" if optional else ""}')
    names = ', '.join(f'"{key}"' for key in properties)
    lines.append(f'    public static let propertyNames: Set<String> = [{names}]')
    lines.append('    public init(' + ', '.join(parameters) + ') {')
    for key in properties:
        lines.append(f'        self.{key} = {key}')
    lines += ['    }', '}']
    return '\n'.join(lines)


values = ', '.join(schema['$defs']['section']['properties']['kind']['enum'])
source = 'import Foundation\n\npublic enum DocumentKind: String, Codable, Sendable { case ' + values + ' }\n\n'
source += declaration('CourseSection', schema['$defs']['section']) + '\n\n' + declaration('CourseManifest', schema) + '\n'
output = ROOT / 'Sources/LearningCore/CourseManifest.swift'
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
if args.check:
    if not output.exists() or output.read_text() != source:
        raise SystemExit('课程模型与 Schema 不一致，请运行 python3 Tools/generate_contract.py')
else:
    output.write_text(source)
