"""Local authenticated transport; the browser worker owns sessions and receipts."""
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
from flask import jsonify, request


def register(app, authenticate, local_mode, app_root):
    lock = threading.Lock()

    @app.post('/api/zendesk/<action>')
    def zendesk_action(action):
        if not local_mode or request.remote_addr not in {'127.0.0.1', '::1'} or request.host.split(':', 1)[0] not in {'localhost', '127.0.0.1'}:
            return jsonify({'message': 'Use a integração local deste computador para acessar o Zendesk.'}), 403
        user, error = authenticate(pairing=True)
        if error is not None:
            return error
        if action not in {'connect', 'capture', 'create', 'register-sla', 'receipt'}:
            return jsonify({'message': 'Ação Zendesk inválida.'}), 400
        body = request.get_json(silent=True)
        if not isinstance(body, dict):
            return jsonify({'message': 'Dados inválidos.'}), 400
        if not lock.acquire(blocking=False):
            return jsonify({'message': 'Uma operação Zendesk está em andamento. Aguarde antes de tentar novamente.'}), 409
        try:
            env = dict(os.environ, PLAYWRIGHT_BROWSERS_PATH=str(Path(app_root) / 'python/ms-playwright'))
            result = subprocess.run([sys.executable, '-m', 'local_edesk.zendesk_workflow'],
                input=json.dumps({'owner': user['sub'], 'action': action, 'data': body}), text=True,
                capture_output=True, timeout=240, cwd=str(app_root), env=env)
            if result.returncode != 0:
                return jsonify({'message': 'A integração Zendesk não concluiu a operação. Confira a instalação local.'}), 503
            data = json.loads(result.stdout)
            return jsonify(data), 200 if data.get('ok') else 400
        except subprocess.TimeoutExpired:
            return jsonify({'message': 'O tempo da operação terminou. Se houve envio, confira o Zendesk antes de repetir.'}), 504
        except Exception:
            return jsonify({'message': 'Não foi possível consultar o resultado. Confira o Zendesk antes de repetir um envio.'}), 503
        finally:
            lock.release()
