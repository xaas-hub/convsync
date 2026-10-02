import { RuleConfigSeverity } from '@commitlint/types';
import conventionalConfig from '@commitlint/config-conventional';

export default {
  extends: ['@commitlint/config-conventional'],
  ignores: [
    (commit) => /\[skip ci\]/m.test(commit),
  ],
  rules: {
    'body-max-line-length': [RuleConfigSeverity.Error, 'always', 150],
    'type-enum': [
      RuleConfigSeverity.Error,
      'always',
      [
        ...conventionalConfig.rules['type-enum'][RuleConfigSeverity.Error],
        'deps', // Add deps for Dependabot
      ],
    ],
  },
}
