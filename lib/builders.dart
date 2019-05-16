// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build/build.dart';
import 'package:widget_template_language/widget_template_language.dart';

Builder widgetTemplateBuilder(BuilderOptions builderOptions) {
  return WidgetTemplateBuilder();
}

class WidgetTemplateBuilder extends Builder {
  @override
  FutureOr<void> build(BuildStep buildStep) async {
    final AssetId outputId = buildStep.inputId.changeExtension('.dart');
    final buffer = StringBuffer();
    final source = await buildStep.readAsString(buildStep.inputId);
    final templateParts = parse(source,
        sourceUrl: buildStep.inputId.uri.toString(), desugar: false);
    final visitor = RenderObjectGenerator();
    buffer.write('''
    import 'package:flutter/widgets.dart';
    import 'package:flutter/material.dart';
    import 'package:flutter/cupertino.dart';

    mixin Template on StatelessWidget {

      @override
      Widget build(BuildContext context) {
        return ''');
    for (var templatePart in templateParts) {
      templatePart.accept(visitor, buffer);
    }
    buffer.write(''';
      }
''');
    for (var input in visitor.inputs) {
      buffer.writeln('get $input;');
    }
    buffer.write('}');
    await buildStep.writeAsString(outputId, buffer.toString());
  }

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.html': ['.dart'],
      };
}

class RenderObjectGenerator extends TemplateAstVisitor<void, StringBuffer> {
  bool inChildren = false;
  final inputs = <String>{};

  @override
  visitElement(ElementAst astNode, [StringBuffer context]) {
    if (astNode.stars.isNotEmpty) {
      final star = astNode.stars.single;
      if (star.name == 'if') {
        context.write('!${star.value} ? const SizedBox() : ');
      }
      if (star.value.startsWith('this.')) {
        inputs.add(star.value.split('this.')[1]);
      }
    }
    context.write(astNode.name);
    context.write('(');

    /// Add constructor arguments.
    for (var attribute in astNode.attributes) {
      final value = attribute.value.trim();
      if (value.startsWith('this.')) {
        inputs.add(attribute.name);
      }
      context.write('${attribute.name}: $value,');
    }
    var params = <String, List<StandaloneTemplateAst>>{};
    for (var child in astNode.childNodes) {
      if (child is TextAst) {
        if (child.value.trim().isEmpty) {
          continue;
        }
        if (params['@@'] == null) {
          params['@@'] = [child];
        } else {
          params['@@'].add(child);
        }
      } else if (child is ElementAst) {
        if (child.annotations.isNotEmpty) {
          var slot = child.annotations.first.name;
          if (params[slot] == null) {
            params[slot] = [child];
          } else {
            params[slot].add(child);
          }
        } else if (child.stars.any((star) => star.name == 'for')) {
          if (params['@@'] == null) {
            params['@@'] = [null, child, null];
          } else {
            params['@@'].add(null);
            params['@@'].add(child);
            params['@@'].add(null);
          }
        } else {
          if (params['@@'] == null) {
            params['@@'] = [child];
          } else {
            params['@@'].add(child);
          }
        }
      } else {
        throw StateError(child.toString());
      }
    }
    bool inForExpression = false;
    bool sawForExpression = false;
    for (var name in params.keys) {
      var value = params[name];
      if ((name == '@@' && value.length == 1) ||
          name == 'child' ||
          (value.length == 1 && name != 'children')) {
        var localName = name == '@@' ? 'child' : name;
        context.write('$localName: ');
        var child = value.single;
        child.accept(this, context);
        context.write(',');
      } else if ((name == '@@' && value.length > 1) ||
          name == 'children' ||
          value.length > 1) {
        var localName = name == '@@' ? 'children' : name;
        context.write('$localName: [');
        for (var child in value) {
          if (!inForExpression && child == null) {
            context.write(']');
            inForExpression = true;
            sawForExpression = true;
            continue;
          } else if (inForExpression && child == null) {
            context.write('..addAll([');
            inForExpression = false;
            continue;
          }
          if (inForExpression) {
            var expr = (child as ElementAst).stars.single;
            var bindings = expr.value.trim().split(RegExp(r'\s+'));
            if (bindings[0] != 'var') {
              throw StateError('');
            }
            var localName = bindings[1];
            if (bindings[2] != 'in') {
              throw StateError('');
            }
            String binding;
            if (bindings[3].startsWith('this.')) {
              binding = bindings[3].split('this.')[1];
              inputs.add(binding);
            } else {
              binding = bindings[3];
            }
            context.write('..addAll($binding.map<Widget>(($localName) => ');
            child.accept(this, context);
            context.write('))');
            continue;
          }
          child.accept(this, context);
          context.write(',');
        }
        context.write('],');
        if (sawForExpression) {
          context.write(')');
        }
      }
    }
    context.write(')');
    return null;
  }

  @override
  visitText(TextAst astNode, [StringBuffer context]) {
    final String value = astNode.value.trim();
    context.write('Text(\'$value\')');
  }

  @override
  visitAttribute(AttributeAst astNode, [StringBuffer context]) {
    return null;
  }

  @override
  visitAnnotation(AnnotationAst astNode, [StringBuffer context]) {
    return null;
  }

  @override
  visitProperty(PropertyAst astNode, [StringBuffer context]) {
    return null;
  }

  @override
  visitBanana(BananaAst astNode, [StringBuffer context]) {
    return null;
  }

  @override
  visitCloseElement(CloseElementAst astNode, [StringBuffer context]) {
    return null;
  }

  @override
  visitComment(CommentAst astNode, [StringBuffer context]) {
    return null;
  }

  @override
  visitEmbeddedContent(EmbeddedContentAst astNode, [StringBuffer context]) {
    throw UnsupportedError('message');
  }

  @override
  visitEvent(EventAst astNode, [StringBuffer context]) {
    return null;
  }

  @override
  visitExpression(ExpressionAst astNode, [StringBuffer context]) {
    return null;
  }

  @override
  visitInterpolation(InterpolationAst astNode, [context]) {
    return null;
  }

  @override
  visitLetBinding(LetBindingAst astNode, [context]) {
    return null;
  }

  @override
  visitReference(ReferenceAst astNode, [context]) {
    return null;
  }

  @override
  visitStar(StarAst astNode, [context]) {
    return null;
  }
}
