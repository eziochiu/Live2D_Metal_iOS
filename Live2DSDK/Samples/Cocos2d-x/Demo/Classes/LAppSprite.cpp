﻿/**
 * Copyright(c) Live2D Inc. All rights reserved.
 *
 * Use of this source code is governed by the Live2D Open Software license
 * that can be found at https://www.live2d.com/eula/live2d-open-software-license-agreement_en.html.
 */

#include "LAppSprite.hpp"
#include "base/CCDirector.h"
#include "LAppPal.hpp"

LAppSprite::LAppSprite(GLuint programId)
{
    // 何番目のattribute変数か
    _positionLocation = glGetAttribLocation(programId, "position");
    _uvLocation      = glGetAttribLocation(programId, "uv");
    _textureLocation = glGetUniformLocation(programId, "texture");
    _colorLocation = glGetUniformLocation(programId, "baseColor");

    _spriteColor[0] = 1.0f;
    _spriteColor[1] = 1.0f;
    _spriteColor[2] = 1.0f;
    _spriteColor[3] = 1.0f;
}

LAppSprite::~LAppSprite()
{
}

void LAppSprite::RenderImmidiate(GLuint textureId, const GLfloat uvVertex[8]) const
{
    // attribute属性を有効にする
    glEnableVertexAttribArray(_positionLocation);
    glEnableVertexAttribArray(_uvLocation);

    // uniform属性の登録
    glUniform1i(_textureLocation, 0);

    // 画面サイズを取得する
    cocos2d::Size visibleSize = cocos2d::Director::getInstance()->getVisibleSize();
    cocos2d::Size winSize = cocos2d::Director::getInstance()->getWinSize();

    // 頂点データ
    float positionVertex[] =
    {
        visibleSize.width / winSize.width, visibleSize.height / winSize.height,
       -visibleSize.width / winSize.width, visibleSize.height / winSize.height,
       -visibleSize.width / winSize.width,-visibleSize.height / winSize.height,
        visibleSize.width / winSize.width,-visibleSize.height / winSize.height,
    };

    // attribute属性を登録
    glVertexAttribPointer(_positionLocation, 2, GL_FLOAT, false, 0, positionVertex);
    glVertexAttribPointer(_uvLocation, 2, GL_FLOAT, false, 0, uvVertex);
    glUniform4f(_colorLocation, _spriteColor[0], _spriteColor[1], _spriteColor[2], _spriteColor[3]);

    // モデルの描画
    glBindTexture(GL_TEXTURE_2D, textureId);
    glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
}

void LAppSprite::SetColor(float r, float g, float b, float a)
{
    _spriteColor[0] = r;
    _spriteColor[1] = g;
    _spriteColor[2] = b;
    _spriteColor[3] = a;
}
